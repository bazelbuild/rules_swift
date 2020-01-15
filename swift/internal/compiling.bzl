# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Implementation of compilation logic for Swift."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":actions.bzl",
    "apply_action_configs",
    "is_action_enabled",
    "run_swift_action",
    "swift_action_names",
)
load(":autolinking.bzl", "register_autolink_extract_action")
load(":debugging.bzl", "ensure_swiftmodule_is_embedded")
load(":derived_files.bzl", "derived_files")
load(
    ":features.bzl",
    "SWIFT_FEATURE_CACHEABLE_SWIFTMODULES",
    "SWIFT_FEATURE_COMPILE_STATS",
    "SWIFT_FEATURE_COVERAGE",
    "SWIFT_FEATURE_DBG",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_FASTBUILD",
    "SWIFT_FEATURE_FULL_DEBUG_INFO",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_MINIMAL_DEPS",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_GENERATED_HEADER",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_OSIZE",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
    "are_all_features_enabled",
    "is_feature_enabled",
)
load(":providers.bzl", "SwiftInfo")
load(":toolchain_config.bzl", "swift_toolchain_config")
load(":utils.bzl", "collect_cc_libraries", "get_providers")

# The number of threads to use for WMO builds, using the same number of cores
# that is on a Mac Pro for historical reasons.
# TODO(b/32571265): Generalize this based on platform and core count
# when an API to obtain this is available.
_DEFAULT_WMO_THREAD_COUNT = 12

def compile_action_configs():
    """Returns the list of action configs needed to perform Swift compilation.

    Toolchains must add these to their own list of action configs so that
    compilation actions will be correctly configured.

    Returns:
        The list of action configs needed to perform compilation.
    """

    #### Flags that control compilation outputs
    action_configs = [
        # Emit object file(s).
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-emit-object"),
            ],
        ),

        # Configure the path to the emitted .swiftmodule file.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_emit_module_path_configurator],
        ),

        # Configure library evolution and the path to the .swiftinterface file.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-enable-library-evolution"),
            ],
            features = [
                SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION,
                SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION,
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_emit_module_interface_path_configurator],
            features = [
                SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION,
                SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION,
                SWIFT_FEATURE_EMIT_SWIFTINTERFACE,
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_emit_objc_header_path_configurator],
            not_features = [SWIFT_FEATURE_NO_GENERATED_HEADER],
        ),

        # Configure the location where compiler performance statistics are
        # dumped.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_stats_output_dir_configurator],
            features = [SWIFT_FEATURE_COMPILE_STATS],
        ),
    ]

    #### Compilation-mode-related flags
    #
    # These configs set flags based on the current compilation mode. They mirror
    # the descriptions of these compilation modes given in the Bazel
    # documentation:
    # https://docs.bazel.build/versions/master/user-manual.html#flag--compilation_mode
    action_configs += [
        # Define appropriate conditional compilation symbols depending on the
        # build mode.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-DDEBUG"),
            ],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FASTBUILD]],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-DNDEBUG"),
            ],
            features = [SWIFT_FEATURE_OPT],
        ),

        # Set the optimization mode. For dbg/fastbuild, use `-O0`. For opt, use
        # `-O` unless the `swift.opt_uses_osize` feature is enabled, then use
        # `-Osize`.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-Onone"),
            ],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FASTBUILD]],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-O"),
            ],
            features = [SWIFT_FEATURE_OPT],
            not_features = [SWIFT_FEATURE_OPT_USES_OSIZE],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-Osize"),
            ],
            features = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_OSIZE],
        ),

        # If the `swift.opt_uses_wmo` feature is enabled, opt builds should also
        # automatically imply whole-module optimization.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-whole-module-optimization"),
            ],
            features = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ),

        # Enable or disable serialization of debugging options into
        # swiftmodules.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xfrontend",
                    "-no-serialize-debugging-options",
                ),
            ],
            features = [SWIFT_FEATURE_CACHEABLE_SWIFTMODULES],
            not_features = [SWIFT_FEATURE_OPT],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xfrontend",
                    "-serialize-debugging-options",
                ),
            ],
            not_features = [
                SWIFT_FEATURE_OPT,
                SWIFT_FEATURE_CACHEABLE_SWIFTMODULES,
            ],
        ),

        # Enable testability if requested.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-enable-testing"),
            ],
            features = [SWIFT_FEATURE_ENABLE_TESTING],
        ),

        # Emit appropriate levels of debug info. On Apple platforms, requesting
        # dSYMs (regardless of compilation mode) forces full debug info because
        # `dsymutil` produces spurious warnings about symbols in the debug map
        # when run on DI emitted by `-gline-tables-only`.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [swift_toolchain_config.add_arg("-g")],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FULL_DEBUG_INFO]],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-gline-tables-only"),
            ],
            features = [SWIFT_FEATURE_FASTBUILD],
            not_features = [SWIFT_FEATURE_FULL_DEBUG_INFO],
        ),

        # Make paths written into debug info workspace-relative.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xwrapped-swift=-debug-prefix-pwd-is-dot",
                ),
            ],
            features = [SWIFT_FEATURE_DEBUG_PREFIX_MAP],
        ),
    ]

    #### Coverage and sanitizer instrumentation flags
    #
    # Note that for the sanitizer flags, we don't define Swift-specific ones;
    # if the underlying C++ toolchain doesn't define them, we don't bother
    # supporting them either.
    action_configs += [
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-profile-generate"),
                swift_toolchain_config.add_arg("-profile-coverage-mapping"),
            ],
            features = [SWIFT_FEATURE_COVERAGE],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-sanitize=address"),
            ],
            features = ["asan"],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-sanitize=thread"),
            ],
            features = ["tsan"],
        ),
    ]

    #### Flags controlling how Swift/Clang modular inputs are processed
    action_configs += [
        # Treat paths in .modulemap files as workspace-relative, not modulemap-
        # relative.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-Xcc", "-Xclang"),
                swift_toolchain_config.add_arg(
                    "-Xcc",
                    "-fmodule-map-file-home-is-cwd",
                ),
            ],
            features = [SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD],
        ),

        # Configure the implicit module cache.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_global_module_cache_configurator],
            features = [SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xwrapped-swift=-ephemeral-module-cache",
                ),
            ],
            not_features = [SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE],
        ),
    ]

    #### Other ClangImporter flags
    action_configs.append(
        # Add `bazel-{bin,genfiles}` to the Clang search path to find generated
        # headers using workspace-relative paths.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_output_dirs_clang_search_paths_configurator],
        ),
    )

    #### Various other Swift compilation flags
    action_configs += [
        # Request color diagnostics, since Bazel pipes the output and causes the
        # driver's TTY check to fail.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xfrontend",
                    "-color-diagnostics",
                ),
            ],
        ),

        # Request batch mode if the compiler supports it. We only do this if the
        # user hasn't requested WMO in some fashion, because otherwise an
        # annoying warning message is emitted. At this level, we can disable the
        # configurator if the `swift.opt` and `swift.opt_uses_wmo` features are
        # both present. Inside the configurator, we also check the user compile
        # flags themselves, since some Swift users enable it there as a build
        # performance hack.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_batch_mode_configurator],
            features = [SWIFT_FEATURE_ENABLE_BATCH_MODE],
            not_features = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ),

        # Set the number of threads to use for WMO.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                partial.make(
                    _wmo_thread_count_configurator,
                    # WMO is implied by features, so don't check the user
                    # compile flags.
                    False,
                ),
            ],
            features = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                partial.make(
                    _wmo_thread_count_configurator,
                    # WMO is not implied by features, so check the user compile
                    # flags in case they enabled it there.
                    True,
                ),
            ],
            not_features = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ),

        # Set the module name.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_module_name_configurator],
        ),
    ]

    # NOTE: The position of this action config in the list is important, because
    # it places user compile flags after flags added by the rules, allowing
    # `copts` attributes and `--swiftcopt` flag values to override flags set by
    # the rule implementations as a last resort.
    action_configs.append(
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_user_compile_flags_configurator],
        ),
    )

    action_configs.append(
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_source_files_configurator],
        ),
    )

    return action_configs

def _emit_module_path_configurator(prerequisites, args):
    """Adds the `.swiftmodule` output path to the command line."""
    args.add("-emit-module-path", prerequisites.swiftmodule_file)

def _emit_module_interface_path_configurator(prerequisites, args):
    """Adds the `.swiftinterface` output path to the command line."""
    args.add("-emit-module-interface-path", prerequisites.swiftinterface_file)

def _emit_objc_header_path_configurator(prerequisites, args):
    """Adds the generated header output path to the command line."""
    args.add("-emit-objc-header-path", prerequisites.generated_header_file)

def _global_module_cache_configurator(prerequisites, args):
    """Adds flags to enable the global module cache."""

    # If bin_dir is not provided, then we don't pass any special flags to
    # the compiler, letting it decide where the cache should live. This is
    # usually somewhere in the system temporary directory.
    if prerequisites.bin_dir:
        args.add(
            "-module-cache-path",
            paths.join(prerequisites.bin_dir.path, "_swift_module_cache"),
        )

def _batch_mode_configurator(prerequisites, args):
    """Adds flags to enable batch compilation mode."""
    if not _is_wmo_manually_requested(prerequisites.user_compile_flags):
        args.add("-enable-batch-mode")

def _output_dirs_clang_search_paths_configurator(prerequisites, args):
    """Adds Clang search paths for the Bazel output directories.

    This allows Swift to find generated headers in `bazel-bin` and
    `bazel-genfiles` even when included using their workspace-relative path,
    matching the behavior used when compiling C/C++/Objective-C.
    """
    if prerequisites.bin_dir:
        args.add_all([
            "-Xcc",
            "-iquote{}".format(prerequisites.bin_dir.path),
        ])

    if prerequisites.genfiles_dir:
        args.add_all([
            "-Xcc",
            "-iquote{}".format(prerequisites.genfiles_dir.path),
        ])

def _module_name_configurator(prerequisites, args):
    """Adds the module name flag to the command line."""
    args.add("-module-name", prerequisites.module_name)

def _stats_output_dir_configurator(prerequisites, args):
    """Adds the compile stats output directory path to the command line."""
    args.add("-stats-output-dir", prerequisites.stats_directory.path)

def _source_files_configurator(prerequisites, args):
    """Adds source files to the command line and required inputs."""
    args.add_all(prerequisites.source_files)
    return swift_toolchain_config.config_result(
        inputs = prerequisites.source_files,
    )

def _user_compile_flags_configurator(prerequisites, args):
    """Adds user compile flags to the command line."""
    args.add_all(prerequisites.user_compile_flags)

def _wmo_thread_count_configurator(should_check_flags, prerequisites, args):
    """Adds thread count flags for WMO compiles to the command line.

    Args:
        should_check_flags: If `True`, WMO wasn't enabled by a feature so the
            user compile flags should be checked for an explicit WMO option.
            This argument is pre-bound when the partial is created for the
            action config. If `False`, unconditionally apply the flags, because
            it is assumed that the configurator was triggered by feature
            satisfaction.
        prerequisites: The action prerequisites.
        args: The `Args` object to which flags will be added.
    """
    if not should_check_flags or (
        should_check_flags and
        _is_wmo_manually_requested(prerequisites.user_compile_flags)
    ):
        # Force threaded mode for WMO builds.
        args.add("-num-threads", str(_DEFAULT_WMO_THREAD_COUNT))

def _is_wmo_manually_requested(user_compile_flags):
    """Returns `True` if a WMO flag is in the given list of compiler flags.

    Args:
        user_compile_flags: A list of compiler flags to scan for WMO usage.

    Returns:
        True if WMO is enabled in the given list of flags.
    """
    return ("-wmo" in user_compile_flags or
            "-whole-module-optimization" in user_compile_flags or
            "-force-single-frontend-invocation" in user_compile_flags)

def compile(
        actions,
        feature_configuration,
        module_name,
        srcs,
        swift_toolchain,
        target_name,
        additional_inputs = [],
        bin_dir = None,
        copts = [],
        defines = [],
        deps = [],
        genfiles_dir = None):
    """Compiles a Swift module.

    Args:
        actions: The context's `actions` object.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `swift_common.derive_module_name` to generate
            a default from the target's label if needed.
        srcs: The Swift source files to compile.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        additional_inputs: A list of `File`s representing additional input files
            that need to be passed to the Swift compile action because they are
            referenced by compiler flags.
        bin_dir: The Bazel `*-bin` directory root. If provided, its path is used
            to store the cache for modules precompiled by Swift's ClangImporter,
            and it is added to ClangImporter's header search paths for
            compatibility with Bazel's C++ and Objective-C rules which support
            includes of generated headers from that location.
        copts: A list of compiler flags that apply to the target being built.
            These flags, along with those from Bazel's Swift configuration
            fragment (i.e., `--swiftcopt` command line flags) are scanned to
            determine whether whole module optimization is being requested,
            which affects the nature of the output files.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        deps: Dependencies of the target being compiled. These targets must
            propagate one of the following providers: `CcInfo`, `SwiftInfo`, or
            `apple_common.Objc`.
        genfiles_dir: The Bazel `*-genfiles` directory root. If provided, its
            path is added to ClangImporter's header search paths for
            compatibility with Bazel's C++ and Objective-C rules which support
            inclusions of generated headers from that location.

    Returns:
        A `struct` containing the following fields:

        *   `generated_header`: A `File` representing the Objective-C header
            that was generated for the compiled module. If no header was
            generated, this field will be None.
        *   `generated_header_module_map`: A `File` representing the module map
            that was generated to correspond to the generated Objective-C
            header. If no module map was generated, this field will be None.
        *   `indexstore`: A `File` representing the directory that contains the
            index store data generated by the compiler if index-while-building
            is enabled. May be None if no indexing was requested.
        *   `linker_flags`: A list of strings representing additional flags that
            should be passed to the linker when linking these objects into a
            binary. If there are none, this field will always be an empty list,
            never None.
        *   `linker_inputs`: A list of `File`s representing additional input
            files (such as those referenced in `linker_flags`) that need to be
            available to the link action when linking these objects into a
            binary. If there are none, this field will always be an empty list,
            never None.
        *   `object_files`: A list of `.o` files that were produced by the
            compiler.
        *   `stats_directory`: A `File` representing the directory that contains
            the timing statistics emitted by the compiler. If no stats were
            requested, this field will be None.
        *   `swiftdoc`: The `.swiftdoc` file that was produced by the compiler.
        *   `swiftinterface`: The `.swiftinterface` file that was produced by
            the compiler. If no interface file was produced (because the
            toolchain does not support them or it was not requested), this field
            will be None.
        *   `swiftmodule`: The `.swiftmodule` file that was produced by the
            compiler.
    """
    is_wmo_implied_by_features = are_all_features_enabled(
        feature_configuration = feature_configuration,
        feature_names = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
    )
    compile_reqs = _declare_compile_outputs(
        actions = actions,
        index_while_building = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_INDEX_WHILE_BUILDING,
        ),
        is_wmo_implied_by_features = is_wmo_implied_by_features,
        srcs = srcs,
        target_name = target_name,
        user_compile_flags = copts + swift_toolchain.command_line_copts,
    )
    output_objects = compile_reqs.output_objects

    swiftmodule = derived_files.swiftmodule(actions, module_name = module_name)
    swiftdoc = derived_files.swiftdoc(actions, module_name = module_name)
    additional_outputs = []

    args = actions.args()

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_RESPONSE_FILES,
    ):
        args.set_param_file_format("multiline")
        args.use_param_file("@%s", use_always = True)

        # Only enable persistent workers if the toolchain supports response
        # files, because the worker unconditionally writes its arguments into
        # one to prevent command line overflow.
        execution_requirements = {"supports-workers": "1"}
    else:
        execution_requirements = {}

    # Emit compilation timing statistics if the user enabled that feature.
    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_COMPILE_STATS,
    ):
        stats_directory = derived_files.stats_directory(actions, target_name)
        additional_outputs.append(stats_directory)
    else:
        stats_directory = None

    args.add_all(compile_reqs.args)

    # Check and enabled features related to the library evolution compilation
    # mode as requested.
    if are_all_features_enabled(
        feature_configuration = feature_configuration,
        feature_names = [
            SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION,
            SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION,
            SWIFT_FEATURE_EMIT_SWIFTINTERFACE,
        ],
    ):
        swiftinterface = derived_files.swiftinterface(
            actions = actions,
            module_name = module_name,
        )
        additional_outputs.append(swiftinterface)
    else:
        swiftinterface = None

    # If supported, generate a Swift header for this library so that it can be
    # included by Objective-C code that depends on it.
    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_NO_GENERATED_HEADER,
    ):
        generated_header = derived_files.objc_header(
            actions = actions,
            target_name = target_name,
        )
        additional_outputs.append(generated_header)

        # Create a module map for the generated header file. This ensures that
        # inclusions of it are treated modularly, not textually.
        #
        # Caveat: Generated module maps are incompatible with the hack that some
        # folks are using to support mixed Objective-C and Swift modules. This
        # trap door lets them escape the module redefinition error, with the
        # caveat that certain import scenarios could lead to incorrect behavior
        # because a header can be imported textually instead of modularly.
        if not is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_NO_GENERATED_MODULE_MAP,
        ):
            generated_module_map = derived_files.module_map(
                actions = actions,
                target_name = target_name,
            )
            write_objc_header_module_map(
                actions = actions,
                module_name = module_name,
                objc_header = generated_header,
                output = generated_module_map,
            )
        else:
            generated_module_map = None
    else:
        generated_header = None
        generated_module_map = None

    prerequisites = struct(
        bin_dir = bin_dir,
        generated_header_file = generated_header,
        genfiles_dir = genfiles_dir,
        module_name = module_name,
        source_files = srcs,
        stats_directory = stats_directory,
        swiftinterface_file = swiftinterface,
        swiftmodule_file = swiftmodule,
        user_compile_flags = copts + swift_toolchain.command_line_copts,
    )

    all_deps = deps + get_implicit_deps(
        feature_configuration = feature_configuration,
        swift_toolchain = swift_toolchain,
    )

    direct_inputs = list(additional_inputs)
    transitive_inputs = _collect_transitive_compile_inputs(
        args = args,
        deps = all_deps,
        direct_defines = defines,
    )

    if swift_toolchain.supports_objc_interop:
        # Collect any additional inputs and flags needed to pull in Objective-C
        # dependencies.
        transitive_inputs.append(_objc_compile_requirements(
            args = args,
            deps = all_deps,
        ))

    # TODO(b/147091143): Completely migrate compilation actions to
    # `run_toolchain_action`.
    action_inputs = apply_action_configs(
        action_name = swift_action_names.COMPILE,
        args = args,
        feature_configuration = feature_configuration,
        prerequisites = prerequisites,
        swift_toolchain = swift_toolchain,
    )

    direct_inputs.extend(action_inputs.inputs)
    transitive_inputs.extend(action_inputs.transitive_inputs)

    all_inputs = depset(
        direct_inputs + compile_reqs.compile_inputs,
        transitive = transitive_inputs + [
            swift_toolchain.cc_toolchain_info.all_files,
        ],
    )
    compile_outputs = ([swiftmodule, swiftdoc] + output_objects +
                       compile_reqs.other_outputs) + additional_outputs

    # TODO(b/147091143): Migrate to `run_toolchain_action`.
    run_swift_action(
        actions = actions,
        action_name = swift_action_names.COMPILE,
        arguments = [args],
        execution_requirements = execution_requirements,
        inputs = all_inputs,
        mnemonic = "SwiftCompile",
        outputs = compile_outputs,
        progress_message = "Compiling Swift module {}".format(module_name),
        swift_toolchain = swift_toolchain,
    )

    linker_flags = []
    linker_inputs = []

    # Object files that should be linked into the binary but not passed to the
    # driver for autolink extraction, because they don't contribute anything
    # meaningful there (e.g., modulewrap outputs).
    objects_excluded_from_autolinking = []

    # Ensure that the .swiftmodule file is embedded in the final library or
    # binary for debugging purposes.
    if _is_debugging(feature_configuration = feature_configuration):
        module_embed_results = ensure_swiftmodule_is_embedded(
            actions = actions,
            feature_configuration = feature_configuration,
            swiftmodule = swiftmodule,
            target_name = target_name,
            swift_toolchain = swift_toolchain,
        )
        linker_flags.extend(module_embed_results.linker_flags)
        linker_inputs.extend(module_embed_results.linker_inputs)
        objects_excluded_from_autolinking.extend(
            module_embed_results.objects_to_link,
        )

    # Invoke an autolink-extract action for toolchains that require it.
    if is_action_enabled(
        action_name = swift_action_names.AUTOLINK_EXTRACT,
        swift_toolchain = swift_toolchain,
    ):
        autolink_file = derived_files.autolink_flags(
            actions,
            target_name = target_name,
        )
        register_autolink_extract_action(
            actions = actions,
            autolink_file = autolink_file,
            feature_configuration = feature_configuration,
            module_name = module_name,
            object_files = output_objects,
            swift_toolchain = swift_toolchain,
        )
        linker_flags.append("@{}".format(autolink_file.path))
        linker_inputs.append(autolink_file)

    output_objects.extend(objects_excluded_from_autolinking)

    return struct(
        generated_header = generated_header,
        generated_module_map = generated_module_map,
        indexstore = compile_reqs.indexstore,
        linker_flags = linker_flags,
        linker_inputs = linker_inputs,
        object_files = output_objects,
        stats_directory = stats_directory,
        swiftdoc = swiftdoc,
        swiftinterface = swiftinterface,
        swiftmodule = swiftmodule,
    )

def get_implicit_deps(feature_configuration, swift_toolchain):
    """Gets the list of implicit dependencies from the toolchain.

    Args:
        feature_configuration: The feature configuration, which determines
            whether optional implicit dependencies are included.
        swift_toolchain: The Swift toolchain.

    Returns:
        A list of targets that should be treated as implicit dependencies of
        the toolchain under the given feature configuration.
    """
    deps = list(swift_toolchain.required_implicit_deps)
    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_MINIMAL_DEPS,
    ):
        deps.extend(swift_toolchain.optional_implicit_deps)
    return deps

def _collect_transitive_compile_inputs(args, deps, direct_defines = []):
    """Collect transitive inputs and flags from Swift providers.

    Args:
        args: An `Args` object to which
        deps: The dependencies for which the inputs should be gathered.
        direct_defines: The list of defines for the target being built, which
            are merged with the transitive defines before they are added to
            `args` in order to prevent duplication.

    Returns:
        A list of `depset`s representing files that must be passed as inputs to
        the Swift compilation action.
    """
    input_depsets = []

    # Collect all the search paths, module maps, flags, and so forth from
    # transitive dependencies.
    transitive_cc_defines = []
    transitive_cc_headers = []
    transitive_cc_includes = []
    transitive_cc_quote_includes = []
    transitive_cc_system_includes = []
    transitive_defines = []
    transitive_modulemaps = []
    transitive_swiftmodules = []
    for dep in deps:
        if SwiftInfo in dep:
            swift_info = dep[SwiftInfo]
            transitive_defines.append(swift_info.transitive_defines)
            transitive_modulemaps.append(swift_info.transitive_modulemaps)
            transitive_swiftmodules.append(swift_info.transitive_swiftmodules)
        if CcInfo in dep:
            compilation_context = dep[CcInfo].compilation_context
            transitive_cc_defines.append(compilation_context.defines)
            transitive_cc_headers.append(compilation_context.headers)
            transitive_cc_includes.append(compilation_context.includes)
            transitive_cc_quote_includes.append(
                compilation_context.quote_includes,
            )
            transitive_cc_system_includes.append(
                compilation_context.system_includes,
            )

    # Add import paths for the directories containing dependencies'
    # swiftmodules.
    all_swiftmodules = depset(transitive = transitive_swiftmodules)
    args.add_all(
        all_swiftmodules,
        format_each = "-I%s",
        map_each = _dirname_map_fn,
        uniquify = True,
    )
    input_depsets.append(all_swiftmodules)

    # Pass Swift defines propagated by dependencies.
    all_defines = depset(direct_defines, transitive = transitive_defines)
    args.add_all(all_defines, format_each = "-D%s")

    # Pass module maps from C/C++ dependencies to ClangImporter.
    # TODO(allevato): Will `CcInfo` eventually keep these in its compilation
    # context?
    all_modulemaps = depset(transitive = transitive_modulemaps)
    input_depsets.append(all_modulemaps)
    args.add_all(
        all_modulemaps,
        before_each = "-Xcc",
        format_each = "-fmodule-map-file=%s",
    )

    # Add C++ headers from dependencies to the action inputs so the compiler can
    # read them.
    input_depsets.append(depset(transitive = transitive_cc_headers))

    # Pass any C++ defines and include search paths to ClangImporter.
    args.add_all(
        depset(transitive = transitive_cc_defines),
        before_each = "-Xcc",
        format_each = "-D%s",
    )
    args.add_all(
        depset(transitive = transitive_cc_includes),
        before_each = "-Xcc",
        format_each = "-I%s",
    )
    args.add_all(
        depset(transitive = transitive_cc_quote_includes),
        before_each = "-Xcc",
        format_each = "-iquote%s",
    )
    args.add_all(
        depset(transitive = transitive_cc_system_includes),
        before_each = "-Xcc",
        format_each = "-isystem%s",
    )

    return input_depsets

def _declare_compile_outputs(
        actions,
        is_wmo_implied_by_features,
        srcs,
        target_name,
        user_compile_flags,
        index_while_building = False):
    """Declares output files and optional output file map for a compile action.

    Args:
        actions: The object used to register actions.
        is_wmo_implied_by_features: `True` if whole module optimization is
            implied by the features set in the feature configuration.
        srcs: The list of source files that will be compiled.
        target_name: The name (excluding package path) of the target being
            built.
        user_compile_flags: The flags that will be passed to the compile action,
            which are scanned to determine whether a single frontend invocation
            will be used or not.
        index_while_building: If `True`, a tree artifact will be declared to
            hold Clang index store data and the relevant option will be added
            during compilation to generate the indexes.

    Returns:
        A `struct` containing the following fields:

        *   `args`: A list of values that should be added to the `Args` of the
            compile action.
        *   `compile_inputs`: Additional input files that should be passed to
            the compile action.
        *   `indexstore`: A `File` representing the index store directory that
            was generated if index-while-building was enabled, or None.
        *   `other_outputs`: Additional output files that should be declared by
            the compile action, but which are not processed further.
        *   `output_groups`: A dictionary of additional output groups that
            should be propagated by the calling rule using the `OutputGroupInfo`
            provider.
        *   `output_objects`: A list of object (.o) files that will be the
            result of the compile action and which should be archived afterward.
    """
    output_nature = _emitted_output_nature(
        is_wmo_implied_by_features = is_wmo_implied_by_features,
        user_compile_flags = user_compile_flags,
    )

    if not output_nature.emits_multiple_objects:
        # If we're emitting a single object, we don't use an object map; we just
        # declare the output file that the compiler will generate and there are
        # no other partial outputs.
        out_obj = derived_files.whole_module_object_file(
            actions = actions,
            target_name = target_name,
        )
        return struct(
            args = ["-o", out_obj],
            compile_inputs = [],
            # TODO(allevato): We need to handle indexing here too.
            indexstore = None,
            other_outputs = [],
            output_groups = {
                "compilation_outputs": depset(direct = [out_obj]),
            },
            output_objects = [out_obj],
        )

    # Otherwise, we need to create an output map that lists the individual
    # object files so that we can pass them all to the archive action.
    output_map_file = derived_files.swiftc_output_file_map(
        actions = actions,
        target_name = target_name,
    )

    # The output map data, which is keyed by source path and will be written to
    # `output_map_file`.
    output_map = {}

    # Object files that will be used to build the archive.
    output_objs = []

    # Additional files, such as partial Swift modules, that must be declared as
    # action outputs although they are not processed further.
    other_outputs = []

    for src in srcs:
        src_output_map = {}

        # Declare the object file (there is one per source file).
        obj = derived_files.intermediate_object_file(
            actions = actions,
            target_name = target_name,
            src = src,
        )
        output_objs.append(obj)
        src_output_map["object"] = obj.path

        # Multi-threaded WMO compiles still produce a single .swiftmodule file,
        # despite producing multiple object files, so we have to check
        # explicitly for that case.
        if output_nature.emits_partial_modules:
            partial_module = derived_files.partial_swiftmodule(
                actions = actions,
                target_name = target_name,
                src = src,
            )
            other_outputs.append(partial_module)
            src_output_map["swiftmodule"] = partial_module.path

        output_map[src.path] = struct(**src_output_map)

    actions.write(
        content = struct(**output_map).to_json(),
        output = output_map_file,
    )

    args = ["-output-file-map", output_map_file]
    output_groups = {
        "compilation_outputs": depset(direct = output_objs),
    }

    # Configure index-while-building if requested. IDEs and other indexing tools
    # can enable this feature on the command line during a build and then access
    # the index store artifacts that are produced.
    if (
        index_while_building and
        not _index_store_path_overridden(user_compile_flags)
    ):
        index_store_dir = derived_files.indexstore_directory(
            actions = actions,
            target_name = target_name,
        )
        other_outputs.append(index_store_dir)
        args.extend(["-index-store-path", index_store_dir.path])
        output_groups["swift_index_store"] = depset(direct = [index_store_dir])
    else:
        index_store_dir = None

    return struct(
        args = args,
        compile_inputs = [output_map_file],
        indexstore = index_store_dir,
        other_outputs = other_outputs,
        output_groups = output_groups,
        output_objects = output_objs,
    )

def find_swift_version_copt_value(copts):
    """Returns the value of the `-swift-version` argument, if found.

    Args:
        copts: The list of copts to be scanned.

    Returns:
        The value of the `-swift-version` argument, or None if it was not found
        in the copt list.
    """

    # Note that the argument can occur multiple times, and the last one wins.
    last_swift_version = None

    count = len(copts)
    for i in range(count):
        copt = copts[i]
        if copt == "-swift-version" and i + 1 < count:
            last_swift_version = copts[i + 1]

    return last_swift_version

def new_objc_provider(
        deps,
        include_path,
        link_inputs,
        linkopts,
        module_map,
        static_archives,
        swiftmodules,
        defines = [],
        objc_header = None):
    """Creates an `apple_common.Objc` provider for a Swift target.

    Args:
        deps: The dependencies of the target being built, whose `Objc` providers
            will be passed to the new one in order to propagate the correct
            transitive fields.
        include_path: A header search path that should be propagated to
            dependents.
        link_inputs: Additional linker input files that should be propagated to
            dependents.
        linkopts: Linker options that should be propagated to dependents.
        module_map: The module map generated for the Swift target's Objective-C
            header, if any.
        static_archives: A list (typically of one element) of the static
            archives (`.a` files) containing the target's compiled code.
        swiftmodules: A list (typically of one element) of the `.swiftmodule`
            files for the compiled target.
        defines: A list of `defines` from the propagating `swift_library` that
            should also be defined for `objc_library` targets that depend on it.
        objc_header: The generated Objective-C header for the Swift target. If
            `None`, no headers will be propagated. This header is only needed
            for Swift code that defines classes that should be exposed to
            Objective-C.

    Returns:
        An `apple_common.Objc` provider that should be returned by the calling
        rule.
    """
    objc_providers = get_providers(deps, apple_common.Objc)
    objc_provider_args = {
        "link_inputs": depset(direct = swiftmodules + link_inputs),
        "providers": objc_providers,
        "uses_swift": True,
    }

    # The link action registered by `apple_binary` only looks at `Objc`
    # providers, not `CcInfo`, for libraries to link. Until that rule is
    # migrated over, we need to collect libraries from `CcInfo` (which will
    # include Swift and C++) and put them into the new `Objc` provider.
    transitive_cc_libs = []
    for cc_info in get_providers(deps, CcInfo):
        static_libs = collect_cc_libraries(
            cc_info = cc_info,
            include_static = True,
        )
        transitive_cc_libs.append(depset(static_libs, order = "topological"))
    objc_provider_args["library"] = depset(
        static_archives,
        transitive = transitive_cc_libs,
        order = "topological",
    )

    if include_path:
        objc_provider_args["include"] = depset(direct = [include_path])
    if defines:
        objc_provider_args["define"] = depset(direct = defines)
    if objc_header:
        objc_provider_args["header"] = depset(direct = [objc_header])
    if linkopts:
        objc_provider_args["linkopt"] = depset(direct = linkopts)

    force_loaded_libraries = [
        archive
        for archive in static_archives
        if archive.basename.endswith(".lo")
    ]
    if force_loaded_libraries:
        objc_provider_args["force_load_library"] = depset(
            direct = force_loaded_libraries,
        )

    # In addition to the generated header's module map, we must re-propagate the
    # direct deps' Objective-C module maps to dependents, because those Swift
    # modules still need to see them. We need to construct a new transitive objc
    # provider to get the correct strict propagation behavior.
    transitive_objc_provider_args = {"providers": objc_providers}
    if module_map:
        transitive_objc_provider_args["module_map"] = depset(
            direct = [module_map],
        )

    transitive_objc = apple_common.new_objc_provider(
        **transitive_objc_provider_args
    )
    objc_provider_args["module_map"] = transitive_objc.module_map

    return apple_common.new_objc_provider(**objc_provider_args)

def _objc_compile_requirements(args, deps):
    """Collects compilation requirements for Objective-C dependencies.

    Args:
        args: An `Args` object to which compile options will be added.
        deps: The `deps` of the target being built.

    Returns:
        A `depset` of files that should be included among the inputs of the
        compile action.
    """
    defines = []
    includes = []
    inputs = []
    module_maps = []
    static_framework_names = []
    all_frameworks = []

    objc_providers = get_providers(deps, apple_common.Objc)

    for objc in objc_providers:
        inputs.append(objc.header)
        inputs.append(objc.umbrella_header)

        defines.append(objc.define)
        includes.append(objc.include)

        static_framework_names.append(objc.static_framework_names)
        all_frameworks.append(objc.framework_search_path_only)

    # Collect module maps for dependencies. These must be pulled from a combined
    # transitive provider to get the correct strict propagation behavior that we
    # use to workaround command-line length issues until Swift 4.2 is available.
    transitive_objc_provider = apple_common.new_objc_provider(
        providers = objc_providers,
    )
    module_maps = transitive_objc_provider.module_map
    inputs.append(module_maps)

    # Add the objc dependencies' header search paths so that imported modules
    # can find their headers.
    args.add_all(depset(transitive = includes), format_each = "-I%s")

    # Add framework search paths for any prebuilt frameworks.
    args.add_all(
        depset(transitive = all_frameworks),
        format_each = "-F%s",
        map_each = paths.dirname,
    )

    # Disable the `LC_LINKER_OPTION` load commands for static framework
    # automatic linking. This is needed to correctly deduplicate static
    # frameworks from also being linked into test binaries where it is also
    # linked into the app binary.
    args.add_all(
        depset(transitive = static_framework_names),
        map_each = _disable_autolink_framework_copts,
    )

    # Swift's ClangImporter does not include the current directory by default in
    # its search paths, so we must add it to find workspace-relative imports in
    # headers imported by module maps.
    args.add_all(["-Xcc", "-iquote."])

    # Ensure that headers imported by Swift modules have the correct defines
    # propagated from dependencies.
    args.add_all(
        depset(transitive = defines),
        before_each = "-Xcc",
        format_each = "-D%s",
    )

    # Take any Swift-compatible defines from Objective-C dependencies and define
    # them for Swift.
    args.add_all(
        depset(transitive = defines),
        map_each = _exclude_swift_incompatible_define,
        format_each = "-D%s",
    )

    # Load module maps explicitly instead of letting Clang discover them in the
    # search paths. This is needed to avoid a case where Clang may load the same
    # header in modular and non-modular contexts, leading to duplicate
    # definitions in the same file.
    # <https://llvm.org/bugs/show_bug.cgi?id=19501>
    args.add_all(
        module_maps,
        before_each = "-Xcc",
        format_each = "-fmodule-map-file=%s",
    )

    return depset(transitive = inputs)

def output_groups_from_compilation_outputs(compilation_outputs):
    """Returns a dictionary of output groups from Swift compilation outputs.

    Args:
        compilation_outputs: The result of calling `swift_common.compile`.

    Returns:
        A `dict` whose keys are the names of output groups and values are
        `depset`s of `File`s, which can be splatted as keyword arguments to the
        `OutputGroupInfo` constructor.
    """
    output_groups = {}

    if compilation_outputs.indexstore:
        output_groups["swift_index_store"] = depset([
            compilation_outputs.indexstore,
        ])

    if compilation_outputs.stats_directory:
        output_groups["swift_compile_stats_direct"] = depset([
            compilation_outputs.stats_directory,
        ])

    if compilation_outputs.swiftinterface:
        output_groups["swiftinterface"] = depset([
            compilation_outputs.swiftinterface,
        ])

    return output_groups

def swift_library_output_map(name, alwayslink):
    """Returns the dictionary of implicit outputs for a `swift_library`.

    This function is used to specify the `outputs` of the `swift_library` rule;
    as such, its arguments must be named exactly the same as the attributes to
    which they refer.

    Args:
        name: The name of the target being built.
        alwayslink: Indicates whether the object files in the library should
            always be always be linked into any binaries that depend on it, even
            if some contain no symbols referenced by the binary.

    Returns:
        The implicit outputs dictionary for a `swift_library`.
    """
    extension = "lo" if alwayslink else "a"
    return {
        "archive": "lib{}.{}".format(name, extension),
    }

def write_objc_header_module_map(
        actions,
        module_name,
        objc_header,
        output):
    """Writes a module map for a generated Swift header to a file.

    Args:
        actions: The context's actions object.
        module_name: The name of the Swift module.
        objc_header: The `File` representing the generated header.
        output: The `File` to which the module map should be written.
    """
    actions.write(
        content = ('module "{module_name}" {{\n' +
                   '  header "../{header_name}"\n' +
                   "}}\n").format(
            header_name = objc_header.basename,
            module_name = module_name,
        ),
        output = output,
    )

def _index_store_path_overridden(copts):
    """Checks if index_while_building must be disabled.

    Index while building is disabled when the copts include a custom
    `-index-store-path`.

    Args:
        copts: The list of copts to be scanned.

    Returns:
        True if the index_while_building must be disabled, otherwise False.
    """
    for opt in copts:
        if opt == "-index-store-path":
            return True
    return False

def _dirname_map_fn(f):
    """Returns the dir name of a file.

    This function is intended to be used as a mapping function for file passed
    into `Args.add`.

    Args:
        f: The file.

    Returns:
        The dirname of the file.
    """
    return f.dirname

def _disable_autolink_framework_copts(framework_name):
    """A `map_each` helper that disables autolinking for the given framework.

    Args:
        framework_name: The name of the framework.

    Returns:
        The list of `swiftc` flags needed to disable autolinking for the given
        framework.
    """
    return collections.before_each(
        "-Xfrontend",
        [
            "-disable-autolink-framework",
            framework_name,
        ],
    )

def _emitted_output_nature(is_wmo_implied_by_features, user_compile_flags):
    """Returns information about the nature of emitted compilation outputs.

    The compiler emits a single object if it is invoked with whole-module
    optimization enabled and is single-threaded (`-num-threads` is not present
    or is equal to 1); otherwise, it emits one object file per source file. It
    also emits a single `.swiftmodule` file for WMO builds, _regardless of
    thread count,_ so we have to treat that case separately.

    Args:
        is_wmo_implied_by_features: Whether WMO is implied by features set in
            the feature configuration.
        user_compile_flags: The options passed into the compile action.

    Returns:
        A struct containing the following fields:

        *   `emits_multiple_objects`: `True` if the Swift frontend emits an
            object file per source file, instead of a single object file for the
            whole module, in a compilation action with the given flags.
        *   `emits_partial_modules`: `True` if the Swift frontend emits partial
            `.swiftmodule` files for the individual source files in a
            compilation action with the given flags.
    """
    is_wmo = (
        is_wmo_implied_by_features or
        _is_wmo_manually_requested(user_compile_flags)
    )

    saw_space_separated_num_threads = False

    # If WMO is enabled, the action config will automatically add
    # `-num-threads 12` to the command line. We need to stage that as our
    # initial default here to ensure that we return the right value if the user
    # compile flags don't otherwise override it.
    num_threads = _DEFAULT_WMO_THREAD_COUNT if is_wmo else 1

    for copt in user_compile_flags:
        if saw_space_separated_num_threads:
            saw_space_separated_num_threads = False
            num_threads = _safe_int(copt)
        elif copt == "-num-threads":
            saw_space_separated_num_threads = True
        elif copt.startswith("-num-threads="):
            num_threads = _safe_int(copt.split("=")[1])

    if not num_threads:
        fail("The value of '-num-threads' must be a positive integer.")

    return struct(
        emits_multiple_objects = not (is_wmo and num_threads == 1),
        emits_partial_modules = not is_wmo,
    )

def _exclude_swift_incompatible_define(define):
    """A `map_each` helper that excludes a define if it is not Swift-compatible.

    This function rejects any defines that are not of the form `FOO=1` or `FOO`.
    Note that in C-family languages, the option `-DFOO` is equivalent to
    `-DFOO=1` so we must preserve both.

    Args:
        define: A string of the form `FOO` or `FOO=BAR` that represents an
        Objective-C define.

    Returns:
        The token portion of the define it is Swift-compatible, or `None`
        otherwise.
    """
    token, equal, value = define.partition("=")
    if (not equal and not value) or (equal == "=" and value == "1"):
        return token
    return None

def _safe_int(s):
    """Returns the base-10 integer value of `s` or `None` if it is invalid.

    This function is needed because `int()` fails the build when passed a string
    that isn't a valid integer, with no way to recover
    (https://github.com/bazelbuild/bazel/issues/5940).

    Args:
        s: The string to be converted to an integer.

    Returns:
        The integer value of `s`, or `None` if was not a valid base 10 integer.
    """
    for i in range(len(s)):
        if s[i] < "0" or s[i] > "9":
            return None
    return int(s)

def _is_debugging(feature_configuration):
    """Returns `True` if the current compilation mode produces debug info.

    We replicate the behavior of the C++ build rules for Swift, which are
    described here:
    https://docs.bazel.build/versions/master/user-manual.html#flag--compilation_mode

    Args:
        feature_configuration: The feature configuration.

    Returns:
        `True` if the current compilation mode produces debug info.
    """
    return (
        is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_DBG,
        ) or is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_FASTBUILD,
        )
    )

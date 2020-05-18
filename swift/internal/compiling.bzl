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
load("@bazel_skylib//lib:types.bzl", "types")
load(
    ":actions.bzl",
    "is_action_enabled",
    "run_toolchain_action",
    "swift_action_names",
)
load(":autolinking.bzl", "register_autolink_extract_action")
load(":debugging.bzl", "ensure_swiftmodule_is_embedded")
load(":derived_files.bzl", "derived_files")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_CACHEABLE_SWIFTMODULES",
    "SWIFT_FEATURE_COMPILE_STATS",
    "SWIFT_FEATURE_COVERAGE",
    "SWIFT_FEATURE_DBG",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_FASTBUILD",
    "SWIFT_FEATURE_FULL_DEBUG_INFO",
    "SWIFT_FEATURE_IMPLICIT_MODULES",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_MINIMAL_DEPS",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_GENERATED_HEADER",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_OSIZE",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_USE_C_MODULES",
    "SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE",
    "SWIFT_FEATURE_VFSOVERLAY",
)
load(":features.bzl", "are_all_features_enabled", "is_feature_enabled")
load(":providers.bzl", "SwiftInfo", "create_swift_info")
load(":toolchain_config.bzl", "swift_toolchain_config")
load(
    ":utils.bzl",
    "collect_cc_libraries",
    "compact",
    "get_providers",
    "struct_fields",
)
load(":vfsoverlay.bzl", "write_vfsoverlay")

# VFS root where all .swiftmodule files will be placed when
# SWIFT_FEATURE_VFSOVERLAY is enabled.
_SWIFTMODULES_VFS_ROOT = "/__build_bazel_rules_swift/swiftmodules"

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

        # Add the single object file or object file map, whichever is needed.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_output_object_or_file_map_configurator],
        ),

        # Emit precompiled Clang modules, and embed all files that were read
        # during compilation into the PCM.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.PRECOMPILE_C_MODULE],
            configurators = [
                swift_toolchain_config.add_arg("-emit-pcm"),
                swift_toolchain_config.add_arg("-Xcc", "-Xclang"),
                swift_toolchain_config.add_arg(
                    "-Xcc",
                    "-fmodules-embed-all-files",
                ),
            ],
        ),

        # Add the output precompiled module file path to the command line.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.PRECOMPILE_C_MODULE],
            configurators = [_output_pcm_file_configurator],
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
                [SWIFT_FEATURE_OPT],
                [SWIFT_FEATURE_CACHEABLE_SWIFTMODULES],
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
            features = [
                [SWIFT_FEATURE_DEBUG_PREFIX_MAP, SWIFT_FEATURE_DBG],
                [SWIFT_FEATURE_DEBUG_PREFIX_MAP, SWIFT_FEATURE_FASTBUILD],
                [SWIFT_FEATURE_DEBUG_PREFIX_MAP, SWIFT_FEATURE_FULL_DEBUG_INFO],
            ],
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
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-Xcc", "-Xclang"),
                swift_toolchain_config.add_arg(
                    "-Xcc",
                    "-fmodule-map-file-home-is-cwd",
                ),
            ],
            features = [SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD],
        ),

        # Configure how implicit modules are handled--either using the module
        # cache, or disabled completely when using explicit modules.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_global_module_cache_configurator],
            features = [
                SWIFT_FEATURE_IMPLICIT_MODULES,
                SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE,
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xwrapped-swift=-ephemeral-module-cache",
                ),
            ],
            features = [SWIFT_FEATURE_IMPLICIT_MODULES],
            not_features = [SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE],
        ),
    ]

    #### Search paths for Swift module dependencies
    action_configs.extend([
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_dependencies_swiftmodules_configurator],
            not_features = [SWIFT_FEATURE_VFSOVERLAY],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                _dependencies_swiftmodules_vfsoverlay_configurator,
            ],
            features = [SWIFT_FEATURE_VFSOVERLAY],
        ),
    ])

    #### Search paths for framework dependencies
    action_configs.append(
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [_framework_search_paths_configurator],
        ),
    )

    #### Other ClangImporter flags
    action_configs.extend([
        # Pass flags to Clang for search paths and propagated defines.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [
                _clang_search_paths_configurator,
                _dependencies_clang_defines_configurator,
            ],
        ),

        # Pass flags to Clang for dependencies' module maps or explicit modules,
        # whichever are being used for this build.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [_dependencies_clang_modules_configurator],
            features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [_dependencies_clang_modulemaps_configurator],
            not_features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
    ])

    #### Various other Swift compilation flags
    action_configs += [
        # Request color diagnostics, since Bazel pipes the output and causes the
        # driver's TTY check to fail.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
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
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [_module_name_configurator],
        ),

        # Configure index-while-building.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_index_while_building_configurator],
            features = [SWIFT_FEATURE_INDEX_WHILE_BUILDING],
        ),

        # User-defined conditional compilation flags (defined for Swift; those
        # passed directly to ClangImporter are handled above).
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_conditional_compilation_flag_configurator],
        ),

        # Disable auto-linking for prebuilt static frameworks.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_static_frameworks_disable_autolink_configurator],
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
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [_source_files_configurator],
        ),
    )

    # Add additional input files to the sandbox (does not modify flags).
    action_configs.append(
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_additional_inputs_configurator],
        ),
    )

    return action_configs

def _output_object_or_file_map_configurator(prerequisites, args):
    """Adds the output file map or single object file to the command line."""
    output_file_map = prerequisites.output_file_map
    if output_file_map:
        args.add("-output-file-map", output_file_map)
        return swift_toolchain_config.config_result(
            inputs = [output_file_map],
        )

    object_files = prerequisites.object_files
    if len(object_files) != 1:
        fail(
            "Internal error: If not using an output file map, there should " +
            "only be a single object file expected as the output, but we " +
            "found: {}".format(object_files),
        )

    args.add("-o", object_files[0])
    return None

def _output_pcm_file_configurator(prerequisites, args):
    """Adds the `.pcm` output path to the command line."""
    args.add("-o", prerequisites.pcm_file)

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

def _clang_search_paths_configurator(prerequisites, args):
    """Adds Clang search paths to the command line."""
    args.add_all(
        depset(transitive = [
            prerequisites.cc_info.compilation_context.includes,
            # TODO(b/146575101): Replace with `objc_info.include` once this bug
            # is fixed. See `_merge_target_providers` below for more details.
            prerequisites.objc_include_paths_workaround,
        ]),
        before_each = "-Xcc",
        format_each = "-I%s",
    )

    # Add Clang search paths for the workspace root and Bazel output roots. The
    # first allows ClangImporter to find headers included using
    # workspace-relative paths when they are referenced from within other
    # headers. The latter allows ClangImporter to find generated headers in
    # `bazel-{bin,genfiles}` even when included using their workspace-relative
    # path, matching the behavior used when compiling C/C++/Objective-C.
    #
    # Note that when `--incompatible_merge_genfiles_directory` is specified,
    # `bin_dir` and `genfiles_dir` will have the same path; the depset will
    # ensure that the `-iquote` flags are deduped.
    direct_quote_includes = ["."]
    if prerequisites.bin_dir:
        direct_quote_includes.append(prerequisites.bin_dir.path)
    if prerequisites.genfiles_dir:
        direct_quote_includes.append(prerequisites.genfiles_dir.path)

    args.add_all(
        depset(
            direct_quote_includes,
            transitive = [
                prerequisites.cc_info.compilation_context.quote_includes,
            ],
        ),
        before_each = "-Xcc",
        format_each = "-iquote%s",
    )

    args.add_all(
        prerequisites.cc_info.compilation_context.system_includes,
        map_each = _filter_out_unsupported_include_paths,
        before_each = "-Xcc",
        format_each = "-isystem%s",
    )

def _dependencies_clang_defines_configurator(prerequisites, args):
    """Adds C/C++ dependencies' preprocessor defines to the command line."""
    all_clang_defines = depset(transitive = [
        prerequisites.cc_info.compilation_context.defines,
    ])
    args.add_all(all_clang_defines, before_each = "-Xcc", format_each = "-D%s")

def _collect_clang_module_inputs(
        cc_info,
        is_swift,
        modules,
        objc_info,
        prefer_precompiled_modules):
    """Collects Clang module-related inputs to pass to an action.

    Args:
        cc_info: The `CcInfo` provider of the target being compiled. The direct
            headers of this provider will be collected as inputs.
        is_swift: If True, this is a Swift compilation; otherwise, it is a
            Clang module compilation.
        modules: A list of module structures (as returned by
            `swift_common.create_module`). The precompiled Clang modules or the
            textual module maps and headers of these modules (depending on the
            value of `prefer_precompiled_modules`) will be collected as inputs.
        objc_info: The `apple_common.Objc` provider of the target being
            compiled.
        prefer_precompiled_modules: If True, precompiled module artifacts should
            be preferred over textual module map files and headers for modules
            that have them. If False, textual module map files and headers
            should always be used.

    Returns:
        A toolchain configuration result (i.e.,
        `swift_toolchain_config.config_result`) that contains the input
        artifacts for the action.
    """
    module_inputs = []
    header_depsets = []

    # Swift compiles (not Clang module compiles) that prefer precompiled modules
    # do not need the full set of transitive headers.
    if cc_info and not (is_swift and prefer_precompiled_modules):
        header_depsets.append(cc_info.compilation_context.headers)

    for module in modules:
        clang_module = module.clang
        module_map = clang_module.module_map
        if prefer_precompiled_modules:
            # If the build prefers precompiled modules, use the .pcm if it
            # exists; otherwise, use the textual module map and the headers for
            # that module (because we only want to propagate the headers that
            # are required, not the full transitive set).
            precompiled_module = clang_module.precompiled_module
            if precompiled_module:
                module_inputs.append(precompiled_module)
            else:
                module_inputs.append(clang_module.module_map)
                module_inputs.extend(
                    clang_module.compilation_context.direct_headers,
                )
                module_inputs.extend(
                    clang_module.compilation_context.direct_textual_headers,
                )
        else:
            # If the build prefers textual module maps and headers, just get the
            # module map for each module; we've already collected the full
            # transitive header set below.
            module_inputs.append(module_map)

    # If we prefer textual module maps and headers for the build, fall back to
    # using the full set of transitive headers.
    if not prefer_precompiled_modules:
        if objc_info:
            header_depsets.append(objc_info.umbrella_header)

    return swift_toolchain_config.config_result(
        inputs = module_inputs,
        transitive_inputs = header_depsets,
    )

def _clang_modulemap_dependency_args(module):
    """Returns `swiftc` arguments for the module map of a Clang module.

    Args:
        module: A struct containing information about the module, as defined by
            `swift_common.create_module`.

    Returns:
        A list of arguments to pass to `swiftc`.
    """
    return [
        "-Xcc",
        "-fmodule-map-file={}".format(module.clang.module_map.path),
    ]

def _clang_module_dependency_args(module):
    """Returns `swiftc` arguments for a precompiled Clang module, if possible.

    If no precompiled module was emitted for this module, then this function
    falls back to the textual module map.

    Args:
        module: A struct containing information about the module, as defined by
            `swift_common.create_module`.

    Returns:
        A list of arguments to pass to `swiftc`.
    """
    if not module.clang.precompiled_module:
        return _clang_modulemap_dependency_args(module)
    return [
        "-Xcc",
        "-fmodule-file={}".format(module.clang.precompiled_module.path),
    ]

def _dependencies_clang_modulemaps_configurator(prerequisites, args):
    """Configures Clang module maps from dependencies."""
    modules = [
        module
        for module in prerequisites.transitive_modules
        if module.clang
    ]

    args.add_all(modules, map_each = _clang_modulemap_dependency_args)

    return _collect_clang_module_inputs(
        cc_info = prerequisites.cc_info,
        is_swift = prerequisites.is_swift,
        modules = modules,
        objc_info = prerequisites.objc_info,
        prefer_precompiled_modules = False,
    )

def _dependencies_clang_modules_configurator(prerequisites, args):
    """Configures precompiled Clang modules from dependencies."""
    modules = [
        module
        for module in prerequisites.transitive_modules
        if module.clang
    ]

    args.add_all(modules, map_each = _clang_module_dependency_args)

    return _collect_clang_module_inputs(
        cc_info = prerequisites.cc_info,
        is_swift = prerequisites.is_swift,
        modules = modules,
        objc_info = prerequisites.objc_info,
        prefer_precompiled_modules = True,
    )

def _framework_search_paths_configurator(prerequisites, args):
    """Add search paths for prebuilt frameworks to the command line."""
    args.add_all(
        prerequisites.cc_info.compilation_context.framework_includes,
        format_each = "-F%s",
    )

def _static_frameworks_disable_autolink_configurator(prerequisites, args):
    """Add flags to disable auto-linking for static prebuilt frameworks.

    This disables the `LC_LINKER_OPTION` load commands for auto-linking when
    importing a static framework. This is needed to correctly deduplicate static
    frameworks from being linked into test binaries when it is also linked into
    the application binary.
    """

    # TODO(b/143301479): This can be removed if we can disable auto-linking
    # universally in the linker invocation. For Clang, we already pass
    # `-fno-autolink`, but Swift doesn't have a similar option (to stop emitting
    # `LC_LINKER_OPTION` load commands unconditionally). However, ld64 has an
    # undocumented `-ignore_auto_link` flag that we could use. In either case,
    # though, this would likely also disable auto-linking for system frameworks,
    # so we would need to model those as explicit dependencies first.
    args.add_all(
        prerequisites.objc_info.static_framework_names,
        map_each = _disable_autolink_framework_copts,
    )

def _dependencies_swiftmodules_configurator(prerequisites, args):
    """Adds `.swiftmodule` files from deps to search paths and action inputs."""
    args.add_all(
        prerequisites.transitive_modules,
        format_each = "-I%s",
        map_each = _swift_module_search_path_map_fn,
        uniquify = True,
    )

    return swift_toolchain_config.config_result(
        inputs = prerequisites.transitive_swiftmodules,
    )

def _dependencies_swiftmodules_vfsoverlay_configurator(prerequisites, args):
    """Provides a single `.swiftmodule` search path using a VFS overlay."""
    swiftmodules = prerequisites.transitive_swiftmodules

    # Bug: `swiftc` doesn't pass its `-vfsoverlay` arg to the frontend.
    # Workaround: Pass `-vfsoverlay` directly via `-Xfrontend`.
    args.add(
        "-Xfrontend",
        "-vfsoverlay{}".format(prerequisites.vfsoverlay_file.path),
    )
    args.add("-I{}".format(prerequisites.vfsoverlay_search_path))

    return swift_toolchain_config.config_result(
        inputs = swiftmodules + [prerequisites.vfsoverlay_file],
    )

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

def _index_while_building_configurator(prerequisites, args):
    """Adds flags for index-store generation to the command line."""
    if not _index_store_path_overridden(prerequisites.user_compile_flags):
        args.add("-index-store-path", prerequisites.indexstore_directory.path)

def _conditional_compilation_flag_configurator(prerequisites, args):
    """Adds (non-Clang) conditional compilation flags to the command line."""
    all_defines = depset(
        prerequisites.defines,
        transitive = [
            prerequisites.transitive_defines,
            # Take any Swift-compatible defines from Objective-C dependencies
            # and define them for Swift.
            prerequisites.cc_info.compilation_context.defines,
        ],
    )
    args.add_all(
        all_defines,
        map_each = _exclude_swift_incompatible_define,
        format_each = "-D%s",
    )

def _additional_inputs_configurator(prerequisites, args):
    """Propagates additional input files to the action.

    This configurator does not add any flags to the command line, but ensures
    that any additional input files requested by the caller of the action are
    available in the sandbox.
    """
    _unused = [args]
    return swift_toolchain_config.config_result(
        inputs = prerequisites.additional_inputs,
    )

def derive_module_name(*args):
    """Returns a derived module name from the given build label.

    For targets whose module name is not explicitly specified, the module name
    is computed by creating an underscore-delimited string from the components
    of the label, replacing any non-identifier characters also with underscores.

    This mapping is not intended to be reversible.

    Args:
        *args: Either a single argument of type `Label`, or two arguments of
            type `str` where the first argument is the package name and the
            second argument is the target name.

    Returns:
        The module name derived from the label.
    """
    if (len(args) == 1 and
        hasattr(args[0], "package") and
        hasattr(args[0], "name")):
        label = args[0]
        package = label.package
        name = label.name
    elif (len(args) == 2 and
          types.is_string(args[0]) and
          types.is_string(args[1])):
        package = args[0]
        name = args[1]
    else:
        fail("derive_module_name may only be called with a single argument " +
             "of type 'Label' or two arguments of type 'str'.")

    package_part = (package.lstrip("//").replace("/", "_").replace("-", "_")
        .replace(".", "_"))
    name_part = name.replace("-", "_")
    if package_part:
        return package_part + "_" + name_part
    return name_part

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
        generated_header_name = None,
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
        generated_header_name: The name of the Objective-C generated header that
            should be generated for this module. If omitted, the name
            `${target_name}-Swift.h` will be used.
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
    compile_outputs, other_outputs = _declare_compile_outputs(
        actions = actions,
        generated_header_name = generated_header_name,
        feature_configuration = feature_configuration,
        module_name = module_name,
        srcs = srcs,
        target_name = target_name,
        user_compile_flags = copts + swift_toolchain.command_line_copts,
    )
    all_compile_outputs = compact([
        # The `.swiftmodule` file is explicitly listed as the first output
        # because it will always exist and because Bazel uses it as a key for
        # various things (such as the filename prefix for param files generated
        # for that action). This guarantees some predictability.
        compile_outputs.swiftmodule_file,
        compile_outputs.swiftdoc_file,
        compile_outputs.swiftinterface_file,
        compile_outputs.generated_header_file,
        compile_outputs.indexstore_directory,
        compile_outputs.stats_directory,
    ]) + compile_outputs.object_files + other_outputs

    # Merge the providers from our dependencies so that we have one each for
    # `SwiftInfo`, `CcInfo`, and `apple_common.Objc`. Then we can pass these
    # into the action prerequisites so that configurators have easy access to
    # the full set of values and inputs through a single accessor.
    all_deps = deps + get_implicit_deps(
        feature_configuration = feature_configuration,
        swift_toolchain = swift_toolchain,
    )
    merged_providers = _merge_targets_providers(
        supports_objc_interop = swift_toolchain.supports_objc_interop,
        targets = all_deps,
    )

    # Flattening this `depset` is necessary because we need to extract the
    # module maps or precompiled modules out of structured values and do so
    # conditionally. This should not lead to poor performance because the
    # flattening happens only once as the action is being registered, rather
    # than the same `depset` being flattened and re-merged multiple times up
    # the build graph.
    transitive_modules = (
        merged_providers.swift_info.transitive_modules.to_list()
    )

    # We need this when generating the VFS overlay file and also when
    # configuring inputs for the compile action, so it's best to precompute it
    # here.
    transitive_swiftmodules = [
        module.swift.swiftmodule
        for module in transitive_modules
        if module.swift
    ]

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_VFSOVERLAY,
    ):
        vfsoverlay_file = derived_files.vfsoverlay(
            actions = actions,
            target_name = target_name,
        )
        write_vfsoverlay(
            actions = actions,
            swiftmodules = transitive_swiftmodules,
            vfsoverlay_file = vfsoverlay_file,
            virtual_swiftmodule_root = _SWIFTMODULES_VFS_ROOT,
        )
    else:
        vfsoverlay_file = None

    prerequisites = struct(
        additional_inputs = additional_inputs,
        bin_dir = bin_dir,
        cc_info = merged_providers.cc_info,
        defines = defines,
        genfiles_dir = genfiles_dir,
        is_swift = True,
        module_name = module_name,
        objc_include_paths_workaround = (
            merged_providers.objc_include_paths_workaround
        ),
        objc_info = merged_providers.objc_info,
        source_files = srcs,
        transitive_defines = merged_providers.swift_info.transitive_defines,
        transitive_modules = transitive_modules,
        transitive_swiftmodules = transitive_swiftmodules,
        user_compile_flags = copts + swift_toolchain.command_line_copts,
        vfsoverlay_file = vfsoverlay_file,
        vfsoverlay_search_path = _SWIFTMODULES_VFS_ROOT,
        # Merge the compile outputs into the prerequisites.
        **struct_fields(compile_outputs)
    )

    run_toolchain_action(
        actions = actions,
        action_name = swift_action_names.COMPILE,
        feature_configuration = feature_configuration,
        outputs = all_compile_outputs,
        prerequisites = prerequisites,
        progress_message = (
            "Compiling Swift module {}".format(module_name)
        ),
        swift_toolchain = swift_toolchain,
    )

    # As part of the full compilation flow, register additional post-compile
    # actions that toolchains may conditionally support for their target
    # platform, like module-wrap or autolink-extract.
    post_compile_results = _register_post_compile_actions(
        actions = actions,
        compile_outputs = compile_outputs,
        feature_configuration = feature_configuration,
        module_name = module_name,
        swift_toolchain = swift_toolchain,
        target_name = target_name,
    )

    return struct(
        generated_header = compile_outputs.generated_header_file,
        generated_module_map = compile_outputs.generated_module_map_file,
        indexstore = compile_outputs.indexstore_directory,
        linker_flags = post_compile_results.linker_flags,
        linker_inputs = post_compile_results.linker_inputs,
        object_files = (
            compile_outputs.object_files +
            post_compile_results.additional_object_files
        ),
        stats_directory = compile_outputs.stats_directory,
        swiftdoc = compile_outputs.swiftdoc_file,
        swiftinterface = compile_outputs.swiftinterface_file,
        swiftmodule = compile_outputs.swiftmodule_file,
    )

def precompile_clang_module(
        actions,
        cc_compilation_context,
        feature_configuration,
        module_map_file,
        module_name,
        swift_toolchain,
        target_name,
        bin_dir = None,
        genfiles_dir = None,
        swift_info = None):
    """Precompiles an explicit Clang module that is compatible with Swift.

    Args:
        actions: The context's `actions` object.
        cc_compilation_context: A `CcCompilationContext` that contains headers
            and other information needed to compile this module. This
            compilation context should contain all headers required to compile
            the module, which includes the headers for the module itself *and*
            any others that must be present on the file system/in the sandbox
            for compilation to succeed. The latter typically refers to the set
            of headers of the direct dependencies of the module being compiled,
            which Clang needs to be physically present before it detects that
            they belong to one of the precompiled module dependencies.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        module_map_file: A textual module map file that defines the Clang module
            to be compiled.
        module_name: The name of the top-level module in the module map that
            will be compiled.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        bin_dir: The Bazel `*-bin` directory root. If provided, its path is used
            to store the cache for modules precompiled by Swift's ClangImporter,
            and it is added to ClangImporter's header search paths for
            compatibility with Bazel's C++ and Objective-C rules which support
            includes of generated headers from that location.
        genfiles_dir: The Bazel `*-genfiles` directory root. If provided, its
            path is added to ClangImporter's header search paths for
            compatibility with Bazel's C++ and Objective-C rules which support
            inclusions of generated headers from that location.
        swift_info: A `SwiftInfo` provider that contains dependencies required
            to compile this module.

    Returns:
        A `File` representing the precompiled module (`.pcm`) file, or `None` if
        the toolchain or target does not support precompiled modules.
    """

    # Exit early if the toolchain does not support precompiled modules or if the
    # feature configuration for the target being built does not want a module to
    # be emitted.
    if not is_action_enabled(
        action_name = swift_action_names.PRECOMPILE_C_MODULE,
        swift_toolchain = swift_toolchain,
    ):
        return None
    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_C_MODULE,
    ):
        return None

    precompiled_module = derived_files.precompiled_module(
        actions = actions,
        target_name = target_name,
    )

    if swift_info:
        transitive_modules = swift_info.transitive_modules.to_list()
    else:
        transitive_modules = []

    prerequisites = struct(
        bin_dir = bin_dir,
        cc_info = CcInfo(compilation_context = cc_compilation_context),
        genfiles_dir = genfiles_dir,
        is_swift = False,
        module_name = module_name,
        objc_include_paths_workaround = depset(),
        objc_info = apple_common.new_objc_provider(),
        pcm_file = precompiled_module,
        source_files = [module_map_file],
        transitive_modules = transitive_modules,
    )

    run_toolchain_action(
        actions = actions,
        action_name = swift_action_names.PRECOMPILE_C_MODULE,
        feature_configuration = feature_configuration,
        outputs = [precompiled_module],
        prerequisites = prerequisites,
        progress_message = "Precompiling C module {}".format(module_name),
        swift_toolchain = swift_toolchain,
    )

    return precompiled_module

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

def _declare_compile_outputs(
        actions,
        generated_header_name,
        feature_configuration,
        module_name,
        srcs,
        target_name,
        user_compile_flags):
    """Declares output files and optional output file map for a compile action.

    Args:
        actions: The object used to register actions.
        generated_header_name: The desired name of the generated header for this
            module, or `None` to use `${target_name}-Swift.h`.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        module_name: The name of the Swift module being compiled.
        srcs: The list of source files that will be compiled.
        target_name: The name (excluding package path) of the target being
            built.
        user_compile_flags: The flags that will be passed to the compile action,
            which are scanned to determine whether a single frontend invocation
            will be used or not.

    Returns:
        A tuple containing two elements:

        *   A `struct` that should be merged into the `prerequisites` of the
            compilation action.
        *   A list of `File`s that represent additional inputs that are not
            needed as configurator prerequisites nor are processed further but
            which should also be tracked as outputs of the compilation action.
    """

    # First, declare "constant" outputs (outputs whose nature doesn't change
    # depending on compilation mode, like WMO vs. non-WMO).
    swiftmodule_file = derived_files.swiftmodule(
        actions = actions,
        module_name = module_name,
    )
    swiftdoc_file = derived_files.swiftdoc(
        actions = actions,
        module_name = module_name,
    )

    if are_all_features_enabled(
        feature_configuration = feature_configuration,
        feature_names = [
            SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION,
            SWIFT_FEATURE_EMIT_SWIFTINTERFACE,
        ],
    ):
        swiftinterface_file = derived_files.swiftinterface(
            actions = actions,
            module_name = module_name,
        )
    else:
        swiftinterface_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_COMPILE_STATS,
    ):
        stats_directory = derived_files.stats_directory(
            actions = actions,
            target_name = target_name,
        )
    else:
        stats_directory = None

    # If supported, generate the Swift header for this library so that it can be
    # included by Objective-C code that depends on it.
    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_NO_GENERATED_HEADER,
    ):
        if generated_header_name:
            generated_header = _declare_validated_generated_header(
                actions = actions,
                generated_header_name = generated_header_name,
            )
        else:
            generated_header = derived_files.default_generated_header(
                actions = actions,
                target_name = target_name,
            )
    else:
        generated_header = None

    # If not disabled, create a module map for the generated header file. This
    # ensures that inclusions of it are treated modularly, not textually.
    #
    # Caveat: Generated module maps are incompatible with the hack that some
    # folks are using to support mixed Objective-C and Swift modules. This
    # trap door lets them escape the module redefinition error, with the
    # caveat that certain import scenarios could lead to incorrect behavior
    # because a header can be imported textually instead of modularly.
    if generated_header and not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_NO_GENERATED_MODULE_MAP,
    ):
        generated_module_map = derived_files.module_map(
            actions = actions,
            target_name = target_name,
        )
        _write_objc_header_module_map(
            actions = actions,
            module_name = module_name,
            objc_header = generated_header,
            output = generated_module_map,
        )
    else:
        generated_module_map = None

    # Now, declare outputs like object files for which there may be one or many,
    # depending on the compilation mode.
    is_wmo_implied_by_features = are_all_features_enabled(
        feature_configuration = feature_configuration,
        feature_names = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
    )
    output_nature = _emitted_output_nature(
        is_wmo_implied_by_features = is_wmo_implied_by_features,
        user_compile_flags = user_compile_flags,
    )

    if not output_nature.emits_multiple_objects:
        # If we're emitting a single object, we don't use an object map; we just
        # declare the output file that the compiler will generate and there are
        # no other partial outputs.
        object_files = [derived_files.whole_module_object_file(
            actions = actions,
            target_name = target_name,
        )]
        other_outputs = []
        output_file_map = None
    else:
        # Otherwise, we need to create an output map that lists the individual
        # object files so that we can pass them all to the archive action.
        output_info = _declare_multiple_outputs_and_write_output_file_map(
            actions = actions,
            emits_partial_modules = output_nature.emits_partial_modules,
            srcs = srcs,
            target_name = target_name,
        )
        object_files = output_info.object_files
        other_outputs = output_info.other_outputs
        output_file_map = output_info.output_file_map

    # Configure index-while-building if requested. IDEs and other indexing tools
    # can enable this feature on the command line during a build and then access
    # the index store artifacts that are produced.
    index_while_building = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_INDEX_WHILE_BUILDING,
    )
    if (
        index_while_building and
        not _index_store_path_overridden(user_compile_flags)
    ):
        indexstore_directory = derived_files.indexstore_directory(
            actions = actions,
            target_name = target_name,
        )
    else:
        indexstore_directory = None

    compile_outputs = struct(
        generated_header_file = generated_header,
        generated_module_map_file = generated_module_map,
        indexstore_directory = indexstore_directory,
        object_files = object_files,
        output_file_map = output_file_map,
        stats_directory = stats_directory,
        swiftdoc_file = swiftdoc_file,
        swiftinterface_file = swiftinterface_file,
        swiftmodule_file = swiftmodule_file,
    )
    return compile_outputs, other_outputs

def _declare_multiple_outputs_and_write_output_file_map(
        actions,
        emits_partial_modules,
        srcs,
        target_name):
    """Declares low-level outputs and writes the output map for a compilation.

    Args:
        actions: The object used to register actions.
        emits_partial_modules: `True` if the compilation action is expected to
            emit partial `.swiftmodule` files (i.e., one `.swiftmodule` file per
            source file, as in a non-WMO compilation).
        srcs: The list of source files that will be compiled.
        target_name: The name (excluding package path) of the target being
            built.

    Returns:
        A `struct` with the following fields:

        *   `object_files`: A list of object files that were declared and
            recorded in the output file map, which should be tracked as outputs
            of the compilation action.
        *   `other_outputs`: A list of additional output files that were
            declared and recorded in the output file map, which should be
            tracked as outputs of the compilation action.
        *   `output_file_map`: A `File` that represents the output file map that
            was written and that should be passed as an input to the compilation
            action via the `-output-file-map` flag.
    """
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
        if emits_partial_modules:
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

    return struct(
        object_files = output_objs,
        other_outputs = other_outputs,
        output_file_map = output_map_file,
    )

def _declare_validated_generated_header(actions, generated_header_name):
    """Validates and declares the explicitly named generated header.

    If the file does not have a `.h` extension or conatins path separators, the
    build will fail.

    Args:
        actions: The context's `actions` object.
        generated_header_name: The desired name of the generated header.

    Returns:
        A `File` that should be used as the output for the generated header.
    """
    if "/" in generated_header_name:
        fail(
            "The generated header for a Swift module may not contain " +
            "directory components (got '{}').".format(generated_header_name),
        )

    extension = paths.split_extension(generated_header_name)[1]
    if extension != ".h":
        fail(
            "The generated header for a Swift module must have a '.h' " +
            "extension (got '{}').".format(generated_header_name),
        )

    return actions.declare_file(generated_header_name)

def _merge_targets_providers(supports_objc_interop, targets):
    """Merges the compilation-related providers for the given targets.

    This function merges the `CcInfo`, `SwiftInfo`, and `apple_common.Objc`
    providers from the given targets into a single provider for each. These
    providers are then meant to be passed as prerequisites to compilation
    actions so that configurators can populate command lines and inputs based on
    their data.

    Args:
        supports_objc_interop: `True` if the current toolchain supports
            Objective-C interop and the `apple_common.Objc` providers should
            also be used to determine compilation flags and inputs. If `False`,
            any `apple_common.Objc` providers in the targets will be ignored.
        targets: The targets whose providers should be merged.

    Returns:
        A `struct` containing the following fields:

        *   `cc_info`: The merged `CcInfo` provider of the targets.
        *   `objc_include_paths_workaround`: A `depset` containing the include
            paths from the given targets that should be passed to ClangImporter.
            This is a workaround for some currently incorrect propagation
            behavior that is being removed in the future.
        *   `objc_info`: The merged `apple_common.Objc` provider of the targets.
        *   `swift_info`: The merged `SwiftInfo` provider of the targets.
    """
    cc_infos = []
    objc_infos = []
    swift_infos = []

    # TODO(b/146575101): This is only being used to preserve the current
    # behavior of strict Objective-C include paths being propagated one more
    # level than they should be. Once the remaining targets that depend on this
    # behavior have been fixed, remove it.
    objc_include_paths_workaround_depsets = []

    for target in targets:
        if CcInfo in target:
            cc_infos.append(target[CcInfo])
        if SwiftInfo in target:
            swift_infos.append(target[SwiftInfo])

        if apple_common.Objc in target and supports_objc_interop:
            objc_infos.append(target[apple_common.Objc])
            objc_include_paths_workaround_depsets.append(
                target[apple_common.Objc].strict_include,
            )

    return struct(
        cc_info = cc_common.merge_cc_infos(cc_infos = cc_infos),
        objc_include_paths_workaround = depset(
            transitive = objc_include_paths_workaround_depsets,
        ),
        objc_info = apple_common.new_objc_provider(providers = objc_infos),
        swift_info = create_swift_info(swift_infos = swift_infos),
    )

def _register_post_compile_actions(
        actions,
        compile_outputs,
        feature_configuration,
        module_name,
        swift_toolchain,
        target_name):
    """Register additional post-compile actions used by some toolchains.

    Args:
        actions: The context's `actions` object.
        compile_outputs: The result of an earlier call to
            `_declare_compile_outputs`.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `swift_common.derive_module_name` to generate
            a default from the target's label if needed.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

    Returns:
        A `struct` with the following fields:

        *   `additional_object_files`: A `list` of additional object files that
            were produced as outputs of the post-compile actions and should be
            linked into a binary.
        *   `linker_flags`: A `list` of flags that should be propagated up to
            the linker invocation of any binary that depends on the target this
            was compiled for.
        *   `linker_inputs`: A `list` of `File`s referenced by `linker_flags`.
    """
    additional_object_files = []

    # Ensure that the .swiftmodule file is embedded in the final library or
    # binary for debugging purposes.
    linker_flags = []
    linker_inputs = []
    if _is_debugging(feature_configuration = feature_configuration):
        module_embed_results = ensure_swiftmodule_is_embedded(
            actions = actions,
            feature_configuration = feature_configuration,
            swiftmodule = compile_outputs.swiftmodule_file,
            swift_toolchain = swift_toolchain,
            target_name = target_name,
        )
        linker_flags.extend(module_embed_results.linker_flags)
        linker_inputs.extend(module_embed_results.linker_inputs)
        additional_object_files.extend(module_embed_results.objects_to_link)

    # Invoke an autolink-extract action for toolchains that require it.
    if is_action_enabled(
        action_name = swift_action_names.AUTOLINK_EXTRACT,
        swift_toolchain = swift_toolchain,
    ):
        autolink_file = derived_files.autolink_flags(
            actions = actions,
            target_name = target_name,
        )
        register_autolink_extract_action(
            actions = actions,
            autolink_file = autolink_file,
            feature_configuration = feature_configuration,
            module_name = module_name,
            object_files = compile_outputs.object_files,
            swift_toolchain = swift_toolchain,
        )
        linker_flags.append("@{}".format(autolink_file.path))
        linker_inputs.append(autolink_file)

    return struct(
        additional_object_files = additional_object_files,
        linker_flags = linker_flags,
        linker_inputs = linker_inputs,
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
        objc_provider_args["linkopt"] = depset(direct = linkopts, order = "topological")

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

def _write_objc_header_module_map(
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

def _swift_module_search_path_map_fn(module):
    """Returns the path to the directory containing a `.swiftmodule` file.

    This function is intended to be used as a mapping function for modules
    passed into `Args.add_all`.

    Args:
        module: The module structure (as returned by
            `swift_common.create_module`) extracted from the transitive
            modules of a `SwiftInfo` provider.

    Returns:
        The dirname of the module's `.swiftmodule` file.
    """
    if module.swift:
        return module.swift.swiftmodule.dirname
    else:
        return None

def _filter_out_unsupported_include_paths(path):
    """Stub for a filter function only used internally."""
    return path

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

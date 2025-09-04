# Copyright 2022 The Bazel Authors. All rights reserved.
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

"""Common configuration for Swift compile actions."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:types.bzl", "types")
load(
    "@build_bazel_rules_swift//swift/internal:action_names.bzl",
    "SWIFT_ACTION_COMPILE",
    "SWIFT_ACTION_COMPILE_CODEGEN",
    "SWIFT_ACTION_COMPILE_MODULE",
    "SWIFT_ACTION_COMPILE_MODULE_INTERFACE",
    "SWIFT_ACTION_PRECOMPILE_C_MODULE",
    "SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT",
    "SWIFT_ACTION_SYNTHESIZE_INTERFACE",
    "all_compile_action_names",
)
load(
    "@build_bazel_rules_swift//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_CACHEABLE_SWIFTMODULES",
    "SWIFT_FEATURE_CHECKED_EXCLUSIVITY",
    "SWIFT_FEATURE_COVERAGE",
    "SWIFT_FEATURE_DBG",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_DISABLE_AVAILABILITY_CHECKING",
    "SWIFT_FEATURE_DISABLE_CLANG_SPI",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_BARE_SLASH_REGEX",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_ENABLE_V6",
    "SWIFT_FEATURE_EXPLICIT_INTERFACE_BUILD",
    "SWIFT_FEATURE_FASTBUILD",
    "SWIFT_FEATURE_FILE_PREFIX_MAP",
    "SWIFT_FEATURE_FULL_DEBUG_INFO",
    "SWIFT_FEATURE_INDEX_INCLUDE_LOCALS",
    "SWIFT_FEATURE_INDEX_SYSTEM_MODULES",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_INTERNALIZE_AT_LINK",
    "SWIFT_FEATURE_LAYERING_CHECK_FOR_C_DEPS",
    "SWIFT_FEATURE_LAYERING_CHECK_SWIFT",
    "SWIFT_FEATURE_MODULAR_INDEXING",
    "SWIFT_FEATURE_MODULE_HOME_IS_CWD",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_ASAN_VERSION_CHECK",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_CMO",
    "SWIFT_FEATURE_OPT_USES_OSIZE",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_REWRITE_GENERATED_HEADER",
    "SWIFT_FEATURE_SYSTEM_MODULE",
    "SWIFT_FEATURE_USE_C_MODULES",
    "SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP",
    "SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE",
    "SWIFT_FEATURE__NUM_THREADS_1_IN_SWIFTCOPTS",
    "SWIFT_FEATURE__WMO_IN_SWIFTCOPTS",
)
load(
    "@build_bazel_rules_swift//swift/internal:optimization.bzl",
    "is_wmo_manually_requested",
)
load(":action_config.bzl", "ActionConfigInfo", "ConfigResultInfo", "add_arg")

visibility([
    "@build_bazel_rules_swift//swift/toolchains/...",
])

# The number of threads to use for WMO builds, using the same number of cores
# that is on a Mac Pro for historical reasons.
# TODO(b/32571265): Generalize this based on platform and core count
# when an API to obtain this is available.
_DEFAULT_WMO_THREAD_COUNT = 12

def compile_action_configs(
        *,
        additional_objc_copts = [],
        additional_swiftc_copts = [],
        configure_precompile_c_module_clang_modules = None,
        generated_header_rewriter = None):
    """Returns the list of action configs needed to perform Swift compilation.

    Toolchains must add these to their own list of action configs so that
    compilation actions will be correctly configured.

    Args:
        additional_objc_copts: An optional list of additional Objective-C
            compiler flags that should be passed (preceded by `-Xcc`) to Swift
            compile actions *and* Swift explicit module precompile actions after
            any other toolchain- or user-provided flags.
        additional_swiftc_copts: An optional list of additional Swift compiler
            flags that should be passed to Swift compile actions only after any
            other toolchain- or user-provided flags.
        configure_precompile_c_module_clang_modules: An optional function that
            configures clang module dependencies for precompiled c modules if
            present. Takes the configurator for clang module dependencies as an
            argument, and returns a list of action configs. Defaults to None.
        generated_header_rewriter: An executable that will be invoked after
            compilation to rewrite the generated header, or None if this is not
            desired.

    Returns:
        The list of action configs needed to perform compilation.
    """

    #### Flags that control compilation outputs
    action_configs = [
        # Emit object file(s).
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-emit-object")],
        ),

        # Add the single object file or object file map, whichever is needed.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_output_object_or_file_map_configurator],
        ),
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_COMPILE_CODEGEN,
                SWIFT_ACTION_COMPILE_MODULE,
            ],
            configurators = [_compile_step_configurator],
        ),

        # Don't embed Clang module breadcrumbs in debug info if we're remapping
        # `.swiftmodule` paths/flags (or not serializing them at all).
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-Xfrontend", "-no-clang-module-breadcrumbs"),
            ],
        ),

        # Emit precompiled Clang modules, and embed all files that were read
        # during compilation into the PCM.
        ActionConfigInfo(
            actions = [SWIFT_ACTION_PRECOMPILE_C_MODULE],
            configurators = [
                add_arg("-emit-pcm"),
                add_arg("-Xcc", "-Xclang"),
                add_arg("-Xcc", "-fmodules-embed-all-files"),
            ],
        ),

        # Add the output precompiled module file path to the command line.
        ActionConfigInfo(
            actions = [SWIFT_ACTION_PRECOMPILE_C_MODULE],
            configurators = [_output_pcm_file_configurator],
        ),

        # Configure the path to the emitted .swiftmodule file.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_emit_module_path_configurator],
        ),

        # Configure library evolution and the path to the .swiftinterface file.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-enable-library-evolution")],
            features = [SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION],
        ),
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_COMPILE,
                SWIFT_ACTION_COMPILE_MODULE,
            ],
            configurators = [_emit_module_interface_path_configurator],
            features = [SWIFT_FEATURE_EMIT_SWIFTINTERFACE],
        ),
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_COMPILE,
                SWIFT_ACTION_COMPILE_MODULE,
            ],
            configurators = [_emit_objc_header_path_configurator],
        ),

        # Emit the list of imported modules for layering checks.
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_COMPILE,
                SWIFT_ACTION_COMPILE_MODULE,
            ],
            configurators = [_swift_layering_check_configurator],
            features = [SWIFT_FEATURE_LAYERING_CHECK_SWIFT],
        ),

        # Configure enforce exclusivity checks if enabled.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-enforce-exclusivity=checked")],
            features = [SWIFT_FEATURE_CHECKED_EXCLUSIVITY],
        ),

        # Configure constant value extraction.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_constant_value_extraction_configurator],
        ),
    ]

    if generated_header_rewriter:
        # Only add the generated header rewriter to the command line and to the
        # action's tool inputs only if the toolchain provides one, the relevant
        # feature is requested, and the particular compilation action is
        # generating a header.
        def generated_header_rewriter_configurator(prerequisites, args):
            additional_tools = []
            if prerequisites.generated_header_file:
                additional_tools.append(depset([generated_header_rewriter]))
                args.add(
                    generated_header_rewriter,
                    format = "-Xwrapped-swift=-generated-header-rewriter=%s",
                )
            return ConfigResultInfo(
                additional_tools = additional_tools,
            )

        action_configs.append(
            ActionConfigInfo(
                actions = [
                    SWIFT_ACTION_COMPILE,
                    SWIFT_ACTION_COMPILE_MODULE,
                ],
                configurators = [generated_header_rewriter_configurator],
                features = [SWIFT_FEATURE_REWRITE_GENERATED_HEADER],
            ),
        )

    #### Compilation-mode-related flags
    #
    # These configs set flags based on the current compilation mode. They mirror
    # the descriptions of these compilation modes given in the Bazel
    # documentation:
    # https://docs.bazel.build/versions/master/user-manual.html#flag--compilation_mode
    action_configs += [
        # Define appropriate conditional compilation symbols depending on the
        # build mode.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-DDEBUG")],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FASTBUILD]],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-DNDEBUG")],
            features = [SWIFT_FEATURE_OPT],
        ),

        # Set the optimization mode. For dbg/fastbuild, use `-O0`. For opt, use
        # `-O` unless the `swift.opt_uses_osize` feature is enabled, then use
        # `-Osize`.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [add_arg("-Onone")],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FASTBUILD]],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [add_arg("-O")],
            features = [SWIFT_FEATURE_OPT],
            not_features = [SWIFT_FEATURE_OPT_USES_OSIZE],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [add_arg("-Osize")],
            features = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_OSIZE],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-disable-cmo")],
            not_features = [SWIFT_FEATURE_OPT_USES_CMO],
        ),

        # If the `swift.opt_uses_wmo` feature is enabled, opt builds should also
        # automatically imply whole-module optimization.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-whole-module-optimization")],
            features = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ),

        # Improve dead-code stripping.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-Xfrontend", "-internalize-at-link")],
            features = [SWIFT_FEATURE_INTERNALIZE_AT_LINK],
        ),

        # Control serialization of debugging options into `.swiftmodules`.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-Xfrontend", "-no-serialize-debugging-options"),
            ],
            features = [SWIFT_FEATURE_CACHEABLE_SWIFTMODULES],
            not_features = [SWIFT_FEATURE_OPT],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-Xfrontend", "-serialize-debugging-options"),
            ],
            not_features = [
                [SWIFT_FEATURE_OPT],
                [SWIFT_FEATURE_CACHEABLE_SWIFTMODULES],
            ],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-Xfrontend", "-prefix-serialized-debugging-options"),
            ],
            not_features = [
                [SWIFT_FEATURE_OPT],
                [SWIFT_FEATURE_CACHEABLE_SWIFTMODULES],
            ],
        ),

        # Enable testability if requested.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-enable-testing")],
            features = [SWIFT_FEATURE_ENABLE_TESTING],
        ),

        # Emit appropriate levels of debug info. On Apple platforms, requesting
        # dSYMs (regardless of compilation mode) forces full debug info because
        # `dsymutil` produces spurious warnings about symbols in the debug map
        # when run on DI emitted by `-gline-tables-only`.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-g")],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FULL_DEBUG_INFO]],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_PRECOMPILE_C_MODULE],
            configurators = [add_arg("-Xcc", "-gmodules")],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FULL_DEBUG_INFO]],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-gline-tables-only")],
            features = [SWIFT_FEATURE_FASTBUILD],
            not_features = [SWIFT_FEATURE_FULL_DEBUG_INFO],
        ),

        # Make paths written into debug info workspace-relative.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
            ],
            configurators = [
                add_arg("-Xwrapped-swift=-debug-prefix-pwd-is-dot"),
            ],
            features = [
                [SWIFT_FEATURE_DEBUG_PREFIX_MAP, SWIFT_FEATURE_DBG],
                [SWIFT_FEATURE_DEBUG_PREFIX_MAP, SWIFT_FEATURE_FASTBUILD],
                [SWIFT_FEATURE_DEBUG_PREFIX_MAP, SWIFT_FEATURE_FULL_DEBUG_INFO],
            ],
            not_features = [SWIFT_FEATURE_FILE_PREFIX_MAP],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
            ],
            configurators = [
                add_arg("-Xwrapped-swift=-file-prefix-pwd-is-dot"),
                add_arg("-file-prefix-map", "__BAZEL_XCODE_DEVELOPER_DIR__=/DEVELOPER_DIR"),
            ],
            features = [SWIFT_FEATURE_FILE_PREFIX_MAP],
        ),
    ]

    #### Coverage and sanitizer instrumentation flags
    #
    # Note that for the sanitizer flags, we don't define Swift-specific ones;
    # if the underlying C++ toolchain doesn't define them, we don't bother
    # supporting them either.
    action_configs += [
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-profile-generate"),
                add_arg("-profile-coverage-mapping"),
            ],
            features = [SWIFT_FEATURE_COVERAGE],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-sanitize=address")],
            features = ["asan"],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-Xllvm", "-asan-guard-against-version-mismatch=0"),
            ],
            features = [
                "asan",
                SWIFT_FEATURE_NO_ASAN_VERSION_CHECK,
            ],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-sanitize=thread")],
            features = ["tsan"],
        ),
    ]

    #### FDO flags
    action_configs.append(
        # Support for order-file instrumentation.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-sanitize=undefined"),
                add_arg("-sanitize-coverage=func"),
            ],
            features = ["fdo_instrument_order_file"],
        ),
    )

    #### Flags controlling how Swift/Clang modular inputs are processed

    action_configs += [
        # When `-g` is passed to the compiler, the driver will pass
        # `-file-compilation-dir <CWD>` to the frontend, which in turn passes
        # `-ffile-compilation-dir <CWD>` to Clang. This CWD is fully resolved so
        # it contains the absolute path to the workspace. If we pass
        # `-file-compilation-dir .`, then the driver/frontend preserve that
        # spelling, ensuring that the ClangImporter options section of the
        # `.swiftmodule` file is hermetic.
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-file-compilation-dir", "."),
            ],
        ),
        # Explicitly set the working directory to ensure that the
        # `FILE_SYSTEM_OPTIONS` block of PCM files is hermetic.
        #
        # IMPORTANT: When writing a PCM file, Clang *unconditionally* includes
        # the working directory in the `FILE_SYSTEM_OPTIONS` block. Thus, the
        # only way to ensure that these files are hermetic is to pass
        # `-working-directory=.`. We cannot pass this to Swift, however, because
        # the driver unfortunately resolves whatever path is given to it and
        # then passes all of the source files as absolute paths to the
        # frontend, which makes other outputs non-hermetic. Therefore, we *only*
        # pass this flag to Clang. Having the two values not be literally
        # identical should still be safe, because we're only passing a value
        # here that is *effectively* the same as the default.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
            ],
            configurators = [
                add_arg("-Xcc", "-working-directory"),
                add_arg("-Xcc", "."),
            ],
            features = [[
                SWIFT_FEATURE_EMIT_C_MODULE,
                SWIFT_FEATURE_USE_C_MODULES,
                SWIFT_FEATURE_MODULE_HOME_IS_CWD,
            ]],
        ),
        # Treat paths embedded into .pcm files as workspace-relative, not
        # modulemap-relative.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
            ],
            configurators = [
                add_arg("-Xcc", "-Xclang"),
                add_arg("-Xcc", "-fmodule-file-home-is-cwd"),
            ],
            features = [[
                SWIFT_FEATURE_EMIT_C_MODULE,
                SWIFT_FEATURE_USE_C_MODULES,
                SWIFT_FEATURE_MODULE_HOME_IS_CWD,
            ]],
        ),
        # Treat paths in .modulemap files as workspace-relative, not modulemap-
        # relative.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [
                add_arg("-Xcc", "-Xclang"),
                add_arg("-Xcc", "-fmodule-map-file-home-is-cwd"),
            ],
            features = [SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD],
        ),

        # Configure how implicit modules are handled--either using the module
        # cache, or disabled completely when using explicit modules.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [_global_module_cache_configurator],
            features = [SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE],
            not_features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [
                add_arg("-Xwrapped-swift=-ephemeral-module-cache"),
            ],
            not_features = [
                [SWIFT_FEATURE_USE_C_MODULES],
                [SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE],
            ],
        ),
        # When using C modules, disable the implicit search for module map files
        # because all of them, including system dependencies, will be provided
        # explicitly.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [add_arg("-Xcc", "-fno-implicit-module-maps")],
            features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        # When using C modules, disable the implicit module cache.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [add_arg("-Xcc", "-fno-implicit-modules")],
            features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_PRECOMPILE_C_MODULE],
            configurators = [_c_layering_check_configurator],
            features = [SWIFT_FEATURE_LAYERING_CHECK_FOR_C_DEPS],
            not_features = [SWIFT_FEATURE_SYSTEM_MODULE],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_PRECOMPILE_C_MODULE],
            configurators = [
                # `-Xclang -emit-module` ought to be unnecessary if `-emit-pcm`
                # is present because ClangImporter configures the invocation to
                # use the `GenerateModule` action. However, it does so *after*
                # creating the invocation by parsing the command line via a
                # helper shared by `-emit-pcm` and other operations, so the
                # changing of the action to `GenerateModule` occurs too late;
                # the argument parser doesn't know that this will be the
                # intended action and it emits a spurious diagnostic:
                # "'-fsystem-module' only allowed with '-emit-module'". So, for
                # system modules we'll pass `-emit-module` as well; it gets rid
                # of the diagnostic and doesn't appear to cause other issues.
                add_arg("-Xcc", "-Xclang"),
                add_arg("-Xcc", "-emit-module"),
                add_arg("-Xcc", "-Xclang"),
                add_arg("-Xcc", "-fsystem-module"),
            ],
            features = [SWIFT_FEATURE_SYSTEM_MODULE],
        ),
    ]

    #### Search paths/explicit module map for Swift module dependencies
    action_configs.extend([
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_explicit_swift_module_map_configurator],
            features = [SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_COMPILE_MODULE_INTERFACE],
            configurators = [
                lambda prerequisites, args: _explicit_swift_module_map_configurator(
                    prerequisites,
                    args,
                    is_frontend = True,
                ),
            ],
            features = [SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_COMPILE_MODULE_INTERFACE],
            configurators = [
                add_arg("-disable-implicit-swift-modules"),
            ],
            features = [SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [_dependencies_swiftmodules_configurator],
            not_features = [SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_module_aliases_configurator],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_plugins_configurator],
        ),
        ActionConfigInfo(
            actions = [
                # TODO: b/351801556 - Verify that this is correct; it may need
                # to be done by the codegen actions.
                SWIFT_ACTION_COMPILE,
                SWIFT_ACTION_COMPILE_MODULE,
            ],
            configurators = [_macro_expansion_configurator],
            # The compiler only generates these in debug builds, unless we pass
            # additional frontend flags. At the current time, we only want to
            # capture these for debug builds.
            not_features = [SWIFT_FEATURE_OPT],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_package_identifier_configurator],
        ),

        # swift-symbolgraph-extract and swift-synthesize-interface don't yet
        # support explicit Swift module maps.
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [_dependencies_swiftmodules_configurator],
        ),
    ])

    #### Search paths for framework dependencies
    action_configs.extend([
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [
                lambda prereqs, args: _framework_search_paths_configurator(
                    prereqs,
                    args,
                    is_swift = True,
                ),
            ],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_PRECOMPILE_C_MODULE],
            configurators = [
                lambda prereqs, args: _framework_search_paths_configurator(
                    prereqs,
                    args,
                    is_swift = False,
                ),
            ],
        ),
    ])

    #### Other ClangImporter flags
    action_configs.extend([
        # Pass flags to Clang for search paths and propagated defines.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [
                _clang_search_paths_configurator,
                _dependencies_clang_defines_configurator,
            ],
        ),

        # Pass flags to Clang for dependencies' module maps or explicit modules,
        # whichever are being used for this build.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [_dependencies_clang_modules_configurator],
            features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [_dependencies_clang_modulemaps_configurator],
            not_features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
    ])

    if configure_precompile_c_module_clang_modules:
        action_configs.extend(configure_precompile_c_module_clang_modules(
            _dependencies_clang_modules_configurator,
        ))
    else:
        action_configs.append(ActionConfigInfo(
            actions = [
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
            ],
            configurators = [_dependencies_clang_modules_configurator],
            features = [SWIFT_FEATURE_USE_C_MODULES],
        ))

    #### Various other Swift compilation flags
    action_configs += [
        # Request color diagnostics, since Bazel pipes the output and causes the
        # driver's TTY check to fail.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
            ],
            configurators = [add_arg("-Xfrontend", "-color-diagnostics")],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_COMPILE_MODULE_INTERFACE],
            configurators = [
                add_arg("-color-diagnostics"),
            ],
        ),

        # Request batch mode if the compiler supports it. We only do this if the
        # user hasn't requested WMO in some fashion, because otherwise an
        # annoying warning message is emitted. At this level, we can disable the
        # configurator if the `swift.opt` and `swift.opt_uses_wmo` features are
        # both present. Inside the configurator, we also check the user compile
        # flags themselves, since some Swift users enable it there as a build
        # performance hack.
        ActionConfigInfo(
            actions = [
                # Only use for legacy Swift compile planning. Parallelized
                # builds cannot use batch mode, because Bazel needs to control
                # the batching directly.
                SWIFT_ACTION_COMPILE,
            ],
            configurators = [_batch_mode_configurator],
            features = [SWIFT_FEATURE_ENABLE_BATCH_MODE],
            not_features = [
                [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
                [SWIFT_FEATURE__WMO_IN_SWIFTCOPTS],
            ],
        ),

        # Set the number of threads to use for WMO. (We can skip this if we know
        # we'll already be applying `-num-threads` via `--swiftcopt` flags.)
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                _make_wmo_thread_count_configurator(
                    # WMO is implied by features, so don't check the user
                    # compile flags.
                    should_check_flags = False,
                ),
            ],
            features = [
                [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
                [SWIFT_FEATURE__WMO_IN_SWIFTCOPTS],
            ],
            not_features = [SWIFT_FEATURE__NUM_THREADS_1_IN_SWIFTCOPTS],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                _make_wmo_thread_count_configurator(
                    # WMO is not implied by features, so check the user compile
                    # flags in case they enabled it there.
                    should_check_flags = True,
                ),
            ],
            not_features = [
                [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
                [SWIFT_FEATURE__NUM_THREADS_1_IN_SWIFTCOPTS],
            ],
        ),

        # Set the module name.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [_module_name_configurator],
        ),

        # Configure index-while-building.
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [_index_while_building_configurator],
            features = [SWIFT_FEATURE_INDEX_WHILE_BUILDING],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [add_arg("-index-include-locals")],
            features = [
                SWIFT_FEATURE_INDEX_WHILE_BUILDING,
                SWIFT_FEATURE_INDEX_INCLUDE_LOCALS,
            ],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-index-ignore-system-modules")],
            features = [SWIFT_FEATURE_INDEX_WHILE_BUILDING],
            not_features = [SWIFT_FEATURE_INDEX_SYSTEM_MODULES],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-index-ignore-clang-modules"),
            ],
            features = [
                SWIFT_FEATURE_INDEX_WHILE_BUILDING,
                SWIFT_FEATURE_MODULAR_INDEXING,
                SWIFT_FEATURE_USE_C_MODULES,
            ],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_PRECOMPILE_C_MODULE],
            configurators = [
                _index_while_building_configurator,
                add_arg("-index-ignore-clang-modules"),
                add_arg("-Xcc", "-index-ignore-pcms"),
            ],
            features = [
                SWIFT_FEATURE_INDEX_WHILE_BUILDING,
                SWIFT_FEATURE_MODULAR_INDEXING,
                # Only index system PCMs since we should have the source code
                # available for most non system modules except for third-party
                # frameworks which we don't have the source code for.
                SWIFT_FEATURE_SYSTEM_MODULE,
            ],
        ),

        # User-defined conditional compilation flags (defined for Swift; those
        # passed directly to ClangImporter are handled above).
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_conditional_compilation_flag_configurator],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [add_arg("-enable-bare-slash-regex")],
            features = [
                SWIFT_FEATURE_ENABLE_BARE_SLASH_REGEX,
            ],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-Xfrontend", "-disable-clang-spi")],
            features = [
                SWIFT_FEATURE_DISABLE_CLANG_SPI,
            ],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-Xfrontend", "-disable-availability-checking")],
            features = [
                SWIFT_FEATURE_DISABLE_AVAILABILITY_CHECKING,
            ],
        ),
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [add_arg("-disable-availability-checking")],
            features = [
                SWIFT_FEATURE_DISABLE_AVAILABILITY_CHECKING,
            ],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_upcoming_and_experimental_features_configurator],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [add_arg("-swift-version", "6")],
            features = [
                SWIFT_FEATURE_ENABLE_V6,
            ],
        ),
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [
                add_arg("-debug-diagnostic-names"),
                _warnings_as_errors_configurator,
            ],
        ),
    ]

    # NOTE: The positions of these action configs in the list are important,
    # because it places the `copts` attribute ("user compile flags") after flags
    # added by the rules, and then the "additional objc" and "additional swift"
    # flags follow those, which are `--objccopt` and `--swiftcopt` flags from
    # the command line that should override even the flags specified in the
    # `copts` attribute.
    action_configs.append(
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [_user_compile_flags_configurator],
        ),
    )
    if additional_objc_copts:
        action_configs.append(
            ActionConfigInfo(
                actions = all_compile_action_names() + [
                    SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                    SWIFT_ACTION_PRECOMPILE_C_MODULE,
                    SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                    SWIFT_ACTION_SYNTHESIZE_INTERFACE,
                ],
                configurators = [
                    lambda _, args: args.add_all(
                        additional_objc_copts,
                        before_each = "-Xcc",
                    ),
                ],
            ),
        )
    if additional_swiftc_copts:
        action_configs.append(
            ActionConfigInfo(
                # TODO(allevato): Determine if there are any uses of
                # `-Xcc`-prefixed flags that need to be added to explicit module
                # actions, or if we should advise against/forbid that.
                actions = all_compile_action_names() + [
                    SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                ],
                configurators = [
                    lambda _, args: args.add_all(
                        additional_swiftc_copts,
                        map_each = _fail_if_flag_is_banned,
                    ),
                ],
            ),
        )

    action_configs.extend([
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
            ],
            configurators = [_source_files_configurator],
        ),

        # If this is an explicit interface build, ensure that the
        # `.swiftinterface` file is among the action inputs but don't add it to
        # the command line because we have a worker-specific flag for that
        # (`-Xwrapped-swift=-explicit-compile-module-from-interface=<path>`).
        # If it's not an explicit interface build, add it to the command line
        # like any other source file.
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [_source_files_as_action_inputs_only_configurator],
            features = [SWIFT_FEATURE_EXPLICIT_INTERFACE_BUILD],
        ),
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
            ],
            configurators = [_source_files_configurator],
            not_features = [SWIFT_FEATURE_EXPLICIT_INTERFACE_BUILD],
        ),
    ])

    # Add additional input files to the sandbox (does not modify flags).
    action_configs.append(
        ActionConfigInfo(
            actions = all_compile_action_names(),
            configurators = [_additional_inputs_configurator],
        ),
    )

    return action_configs

def command_line_objc_copts(compilation_mode, cpp_fragment, objc_fragment):
    """Returns copts that should be passed to `clang` from the `objc` fragment.

    Args:
        compilation_mode: The current compilation mode.
        cpp_fragment: The `cpp` configuration fragment.
        objc_fragment: The `objc` configuration fragment.

    Returns:
        A list of `clang` copts, each of which is preceded by `-Xcc` so that
        they can be passed through `swiftc` to its underlying ClangImporter
        instance.
    """

    # In general, every compilation mode flag from native `objc_*` rules should
    # be passed, but `-g` seems to break Clang module compilation. Since this
    # flag does not make much sense for module compilation and only touches
    # headers, it's ok to omit.
    # TODO(b/153867054): These flags were originally being set by Bazel's legacy
    # hardcoded Objective-C behavior, which has been migrated to crosstool. In
    # the long term, we should query crosstool for the flags we're interested in
    # and pass those to ClangImporter, and do this across all platforms. As an
    # immediate short-term workaround, we preserve the old behavior by passing
    # the exact set of flags that Bazel was originally passing if the list we
    # get back from the configuration fragment is empty.
    legacy_copts = objc_fragment.copts_for_current_compilation_mode
    if not legacy_copts:
        if compilation_mode == "dbg":
            legacy_copts = [
                "-O0",
                "-DDEBUG=1",
                "-fstack-protector",
                "-fstack-protector-all",
            ]
        elif compilation_mode == "opt":
            legacy_copts = [
                "-Os",
                "-DNDEBUG=1",
                "-Wno-unused-variable",
                "-Winit-self",
                "-Wno-extra",
            ]

    clang_copts = cpp_fragment.objccopts + legacy_copts
    return [copt for copt in clang_copts if copt != "-g"]

def _output_object_or_file_map_configurator(prerequisites, args):
    """Adds the output file map or single object file to the command line."""
    output_file_map = prerequisites.output_file_map
    if output_file_map:
        args.add("-output-file-map", output_file_map)
        return ConfigResultInfo(
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

def _compile_step_configurator(prerequisites, args):
    """Adds the parallelized compilation plan step to the command line."""
    step = prerequisites.compile_step
    args.add("-Xwrapped-swift=-compile-step={}={}".format(
        step.action,
        step.output,
    ))

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
    if prerequisites.generated_header_file:
        args.add("-emit-objc-header-path", prerequisites.generated_header_file)

def _swift_layering_check_configurator(prerequisites, args):
    """Adds flags for Swift layering checks to the command line."""
    args.add(
        "-Xwrapped-swift=-layering-check-deps-modules={}".format(
            prerequisites.deps_modules_file.path,
        ),
    )
    return ConfigResultInfo(
        inputs = [prerequisites.deps_modules_file],
    )

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
    if not is_wmo_manually_requested(prerequisites.user_compile_flags):
        args.add("-enable-batch-mode")

def _c_layering_check_configurator(prerequisites, args):
    # We do not enforce layering checks for the Objective-C header generated by
    # Swift, because we don't have predictable control over the imports that it
    # generates. Due to modular re-exports (which are especially common among
    # system frameworks), it may generate an import declaration for a particular
    # symbol from a different module than the Swift code imported it from.
    if not prerequisites.is_swift_generated_header:
        args.add("-Xcc", "-fmodules-strict-decluse")
    return None

def _clang_search_paths_configurator(prerequisites, args):
    """Adds Clang search paths to the command line."""
    args.add_all(
        prerequisites.cc_compilation_context.includes,
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
            transitive = [prerequisites.cc_compilation_context.quote_includes],
        ),
        before_each = "-Xcc",
        format_each = "-iquote%s",
    )

    args.add_all(
        prerequisites.cc_compilation_context.system_includes,
        before_each = "-Xcc",
        format_each = "-isystem%s",
    )

def _dependencies_clang_defines_configurator(prerequisites, args):
    """Adds C/C++ dependencies' preprocessor defines to the command line."""
    all_clang_defines = depset(transitive = [
        prerequisites.cc_compilation_context.defines,
    ])
    args.add_all(all_clang_defines, before_each = "-Xcc", format_each = "-D%s")

def _collect_clang_module_inputs(
        always_include_headers,
        explicit_module_compilation_context,
        mixed_module_clang_inputs,
        modules,
        prefer_precompiled_modules):
    """Collects Clang module-related inputs to pass to an action.

    Args:
        always_include_headers: If True, pass the transitive headers as inputs
            to the compilation action, even if doing an explicit module
            compilation.
        explicit_module_compilation_context: The `CcCompilationContext` of the
            target being compiled, if the inputs are being collected for an
            explicit module compilation action. This parameter should be `None`
            if inputs are being collected for Swift compilation.
        mixed_module_clang_inputs: A `struct` containing the module map and
            precompiled module for the C/Objective-C half of a mixed C/Swift
            module, or None if they are not applicable.
        modules: A list of module structures (as returned by
            `create_swift_module_context`). The precompiled Clang modules or the
            textual module maps and headers of these modules (depending on the
            value of `prefer_precompiled_modules`) will be collected as inputs.
        prefer_precompiled_modules: If True, precompiled module artifacts should
            be preferred over textual module map files and headers for modules
            that have them. If False, textual module map files and headers
            should always be used.

    Returns:
        A toolchain configuration result (i.e.,
        `swift_toolchain_config.config_result`) that contains the input
        artifacts for the action.
    """
    direct_inputs = []
    transitive_inputs = []

    if explicit_module_compilation_context:
        # This is a `SwiftPrecompileCModule` action, so by definition we're
        # only here in a build with explicit modules enabled. We should only
        # need the direct headers of the module being compiled and its
        # direct dependencies (the latter because Clang needs them present
        # on the file system to map them to the module that contains them.)
        # However, we may also need some of the transitive headers, if the
        # module has dependencies that aren't recognized as modules (e.g.,
        # `cc_library` targets without an aspect hint) and the module's
        # headers include those. This will likely over-estimate the needed
        # inputs, but we can't do better without include scanning in
        # Starlark.
        transitive_inputs.append(explicit_module_compilation_context.headers)
        transitive_inputs.append(
            depset(explicit_module_compilation_context.direct_textual_headers),
        )

    for module in modules:
        clang_module = module.clang

        # Add the module map, which we use for both implicit and explicit module
        # builds.
        module_map = clang_module.module_map
        if not module.is_system and type(module_map) == "File":
            direct_inputs.append(module_map)

        precompiled_module = clang_module.precompiled_module
        use_precompiled_module = (
            prefer_precompiled_modules and precompiled_module
        )

        if use_precompiled_module:
            # For builds preferring explicit modules, use it if we have it
            # and don't include any headers as inputs.
            direct_inputs.append(precompiled_module)

        if not use_precompiled_module or always_include_headers:
            # If we don't have an explicit module (or we're not using it), we
            # need the transitive headers from the compilation context
            # associated with the module. This will likely overestimate the
            # headers that will actually be used in the action, but until we can
            # use include scanning from Starlark, we can't compute a more
            # precise input set.
            compilation_context = clang_module.compilation_context
            transitive_inputs.append(compilation_context.headers)
            transitive_inputs.append(
                depset(compilation_context.direct_textual_headers),
            )

    if mixed_module_clang_inputs:
        if mixed_module_clang_inputs.module_map_file:
            direct_inputs.append(mixed_module_clang_inputs.module_map_file)
        if mixed_module_clang_inputs.precompiled_module:
            direct_inputs.append(mixed_module_clang_inputs.precompiled_module)
        if mixed_module_clang_inputs.vfs_overlay_file:
            direct_inputs.append(mixed_module_clang_inputs.vfs_overlay_file)

    return ConfigResultInfo(
        inputs = direct_inputs,
        transitive_inputs = transitive_inputs,
    )

def _clang_modulemap_dependency_args(module, ignore_system = True):
    """Returns a `swiftc` argument for the module map of a Clang module.

    Args:
        module: A struct containing information about the module, as defined by
            `create_swift_module_context`.
        ignore_system: If `True` and the module is a system module, no flag
            should be returned. Defaults to `True`.

    Returns:
        A list of arguments, possibly empty, to pass to `swiftc` (without the
        `-Xcc` prefix).
    """
    module_map = module.clang.module_map

    if (module.is_system and ignore_system) or not module_map:
        return []

    if type(module_map) == "File":
        module_map_path = module_map.path
    else:
        module_map_path = module_map

    return ["-fmodule-map-file={}".format(module_map_path)]

def _clang_module_dependency_args(module):
    """Returns `swiftc` arguments for a precompiled Clang module, if possible.

    If a precompiled module is present for this module, then flags for both it
    and the module map are returned (the latter is required in order to map
    headers to modules in some scenarios, since the precompiled modules are
    passed by name). If no precompiled module is present for this module, then
    this function falls back to the textual module map alone.

    Args:
        module: A struct containing information about the module, as defined by
            `create_swift_module_context`.

    Returns:
        A list of arguments, possibly empty, to pass to `swiftc` (without the
        `-Xcc` prefix).
    """
    if module.clang.precompiled_module:
        # If we're consuming an explicit module, we must also provide the
        # textual module map, whether or not it's a system module.
        return [
            "-fmodule-file={}={}".format(
                module.name,
                module.clang.precompiled_module.path,
            ),
        ] + _clang_modulemap_dependency_args(module, ignore_system = False)
    else:
        # If we have no explicit module, then only include module maps for
        # non-system modules.
        return _clang_modulemap_dependency_args(module)

def _dependencies_clang_modulemaps_configurator(prerequisites, args):
    """Configures Clang module maps from dependencies."""
    modules = [
        module
        for module in prerequisites.transitive_modules
        if module.clang
    ]

    # Uniquify the arguments because different modules might be defined in the
    # same module map file, so it only needs to be present once on the command
    # line.
    args.add_all(
        modules,
        before_each = "-Xcc",
        map_each = _clang_modulemap_dependency_args,
        uniquify = True,
    )

    if prerequisites.is_swift:
        mixed_inputs = getattr(prerequisites, "mixed_module_clang_inputs", None)
        compilation_context = None
    else:
        mixed_inputs = None
        compilation_context = prerequisites.cc_compilation_context

    return _collect_clang_module_inputs(
        always_include_headers = getattr(
            prerequisites,
            "always_include_headers",
            False,
        ),
        explicit_module_compilation_context = compilation_context,
        mixed_module_clang_inputs = mixed_inputs,
        modules = modules,
        prefer_precompiled_modules = False,
    )

def _dependencies_clang_modules_configurator(prerequisites, args, include_modules = True):
    """Configures precompiled Clang modules from dependencies."""
    if include_modules:
        modules = [
            module
            for module in prerequisites.transitive_modules
            if module.clang
        ]
    else:
        modules = []

    # Uniquify the arguments because different modules might be defined in the
    # same module map file, so it only needs to be present once on the command
    # line.
    args.add_all(
        modules,
        before_each = "-Xcc",
        map_each = _clang_module_dependency_args,
        uniquify = True,
    )

    if prerequisites.is_swift:
        # If this is the Swift compilation of a mixed C/Swift module, then we
        # have already precompiled the C half of the module. Add the flags to
        # import it.
        mixed_inputs = getattr(prerequisites, "mixed_module_clang_inputs", None)
        if mixed_inputs and mixed_inputs.module_name:
            args.add("-import-underlying-module")
            if mixed_inputs.vfs_overlay_file:
                # Note that `-ivfsoverlay` and the path must be separate
                # arguments. The frontend does not give the joined form the
                # special treatment that we need to avoid serializing the flag.
                args.add_all(
                    ["-ivfsoverlay", mixed_inputs.vfs_overlay_file],
                    before_each = "-Xcc",
                )
            args.add_all(
                [mixed_inputs.virtual_module_map_path or
                 mixed_inputs.module_map_file],
                format_each = "-fmodule-map-file=%s",
                before_each = "-Xcc",
            )
            if mixed_inputs.precompiled_module:
                args.add_all(
                    [mixed_inputs.virtual_precompiled_module_path or
                     mixed_inputs.precompiled_module],
                    format_each = "-fmodule-file={}=%s".format(
                        mixed_inputs.module_name,
                    ),
                    before_each = "-Xcc",
                )

        compilation_context = None

    else:
        mixed_inputs = None
        compilation_context = prerequisites.cc_compilation_context

    return _collect_clang_module_inputs(
        always_include_headers = getattr(
            prerequisites,
            "always_include_headers",
            False,
        ),
        explicit_module_compilation_context = compilation_context,
        mixed_module_clang_inputs = mixed_inputs,
        modules = modules,
        prefer_precompiled_modules = True,
    )

def _framework_search_paths_configurator(prerequisites, args, is_swift):
    """Add search paths for prebuilt frameworks to the command line."""

    # Swift doesn't automatically propagate its `-F` flag to ClangImporter, so
    # we add it manually with `-Xcc` below (for both regular compilations, in
    # case they're using implicit modules, and Clang module compilations). We
    # don't need to add regular `-F` if this is a Clang module compilation,
    # though, since it won't be used.

    framework_includes = prerequisites.cc_compilation_context.framework_includes
    if is_swift:
        args.add_all(
            framework_includes,
            format_each = "-F%s",
        )
    args.add_all(
        framework_includes,
        format_each = "-F%s",
        before_each = "-Xcc",
    )

def _swift_module_search_path_map_fn(module):
    """Returns the path to the directory containing a `.swiftmodule` file.

    This function is intended to be used as a mapping function for modules
    passed into `Args.add_all`.

    Args:
        module: The module structure (as returned by
            `create_swift_module_context`) extracted from the transitive
            modules of a `SwiftInfo` provider.

    Returns:
        The dirname of the module's `.swiftmodule` file.
    """
    if module.swift:
        search_path = module.swift.swiftmodule.dirname

        # If the dirname also ends in .swiftmodule, remove it as well so that
        # the compiler finds the module *directory*.
        if search_path.endswith(".swiftmodule"):
            search_path = paths.dirname(search_path)

        return search_path
    else:
        return None

def _module_alias_flags(*, original, alias):
    """Returns compiler flags to set the given module alias."""

    return [
        "-module-alias",
        "{original}={alias}".format(
            original = original,
            alias = alias,
        ),
    ]

def _module_alias_map_fn(module):
    """Returns compiler flags to alias the given module.

    This function is intended to be used as a mapping function for modules
    passed into `Args.add_all`.

    Args:
        module: The module structure (as returned by
            `create_swift_module_context`) extracted from the transitive
            modules of a `SwiftInfo` provider.

    Returns:
        The flags to pass to the compiler to alias the given module, or `None`
        if no alias applies.
    """
    if module.name != module.source_name:
        return _module_alias_flags(
            original = module.source_name,
            alias = module.name,
        )
    else:
        return None

def _dependencies_swiftmodules_configurator(prerequisites, args):
    """Adds `.swiftmodule` files from deps to search paths and action inputs."""
    args.add_all(
        prerequisites.transitive_modules,
        format_each = "-I%s",
        map_each = _swift_module_search_path_map_fn,
        uniquify = True,
    )

    return ConfigResultInfo(
        inputs = prerequisites.transitive_swiftmodules,
    )

def _module_aliases_configurator(prerequisites, args):
    """Adds `-module-alias` flags for the active module mapping, if any."""
    args.add_all(
        prerequisites.transitive_modules,
        map_each = _module_alias_map_fn,
    )

    def _already_contains_source_module_name(module_contexts, name):
        for module_context in module_contexts:
            if module_context.source_name == name:
                return True
        return False

    # Add an alias for the module currently being compiled if necessary. Only do
    # this if it's not already one of the transitive modules above, which will
    # be the case for `swift_overlay`s (the underlying C module will be in that
    # list), since the compiler will reject the duplicate alias flag.
    if (prerequisites.original_module_name and
        prerequisites.original_module_name != prerequisites.module_name and
        not _already_contains_source_module_name(
            module_contexts = prerequisites.transitive_modules,
            name = prerequisites.original_module_name,
        )):
        args.add_all(
            _module_alias_flags(
                original = prerequisites.original_module_name,
                alias = prerequisites.module_name,
            ),
        )

def _load_executable_plugin_map_fn(plugin):
    """Returns frontend flags to load compiler plugins."""
    return [
        "-load-plugin-executable",
        "{executable}#{module_names}".format(
            executable = plugin.executable.path,
            module_names = ",".join(plugin.module_names.to_list()),
        ),
    ]

def _plugins_configurator(prerequisites, args):
    """Adds `-load-plugin-executable` flags for required plugins, if any."""
    args.add_all(
        prerequisites.plugins,
        before_each = "-Xfrontend",
        map_each = _load_executable_plugin_map_fn,
    )

    return ConfigResultInfo(
        inputs = [p.executable for p in prerequisites.plugins],
    )

def _macro_expansion_configurator(prerequisites, args):
    """Adds flags to control where macro expansions are generated."""
    args.add(
        prerequisites.macro_expansion_directory.path,
        format = "-Xwrapped-swift=-macro-expansion-dir=%s",
    )

    return None

def _explicit_swift_module_map_configurator(prerequisites, args, is_frontend = False):
    """Adds the explicit Swift module map file to the command line."""
    if is_frontend:
        # If we're calling frontend directly we don't need to prepend each
        # argument with -Xfrontend. Doing so will crash the invocation.
        args.add(
            "-explicit-swift-module-map-file",
            prerequisites.explicit_swift_module_map_file,
        )
    else:
        args.add_all(
            [
                "-explicit-swift-module-map-file",
                prerequisites.explicit_swift_module_map_file,
            ],
            before_each = "-Xfrontend",
        )
    return ConfigResultInfo(
        inputs = prerequisites.transitive_swiftmodules + [
            prerequisites.explicit_swift_module_map_file,
        ],
    )

def _module_name_configurator(prerequisites, args):
    """Adds the module name flag to the command line."""
    args.add("-module-name", prerequisites.module_name)

def _index_while_building_configurator(prerequisites, args):
    """Adds flags for indexstore generation to the command line."""
    args.add("-index-store-path", prerequisites.indexstore_directory.path)
    index_output_path = getattr(prerequisites, "index_unit_output_path", None)
    if index_output_path:
        args.add("-Xcc", "-index-unit-output-path")
        args.add("-Xcc", index_output_path)

def _source_files_configurator(prerequisites, args):
    """Adds source files to the command line and required inputs."""
    args.add_all(prerequisites.source_files)
    return _source_files_as_action_inputs_only_configurator(prerequisites, args)

def _source_files_as_action_inputs_only_configurator(prerequisites, _args):
    """Adds source files to the required inputs but not the command line.

    This configurator assumes that the source files are already provided to the
    command line through some other means (for example, through a
    worker-specific flag).
    """

    # Only add source files to the input file set if they are not strings (for
    # example, the module map of a system framework will be passed in as a file
    # path relative to the SDK root, not as a `File` object).
    return ConfigResultInfo(
        inputs = [
            source_file
            for source_file in prerequisites.source_files
            if not types.is_string(source_file)
        ],
    )

def _user_compile_flags_configurator(prerequisites, args):
    """Adds user compile flags to the command line."""
    args.add_all(
        prerequisites.user_compile_flags,
        map_each = _fail_if_flag_is_banned,
    )

def _make_wmo_thread_count_configurator(should_check_flags):
    """Adds thread count flags for WMO compiles to the command line.

    Args:
        should_check_flags: If `True`, WMO wasn't enabled by a feature so the
            user compile flags should be checked for an explicit WMO option. If
            `False`, unconditionally apply the flags, because it is assumed that
            the configurator was triggered by feature satisfaction.

    Returns:
        A function used to configure the `-num-threads` flag for WMO.
    """

    def _add_num_threads(args):
        args.add("-num-threads", str(_DEFAULT_WMO_THREAD_COUNT))

    if not should_check_flags:
        return lambda _prerequisites, args: _add_num_threads(args)

    def _flag_checking_wmo_thread_count_configurator(prerequisites, args):
        if is_wmo_manually_requested(prerequisites.user_compile_flags):
            _add_num_threads(args)

    return _flag_checking_wmo_thread_count_configurator

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

def _conditional_compilation_flag_configurator(prerequisites, args):
    """Adds (non-Clang) conditional compilation flags to the command line."""
    all_defines = depset(
        prerequisites.defines,
        transitive = [
            # Take any Swift-compatible defines from Objective-C dependencies
            # and define them for Swift.
            prerequisites.cc_compilation_context.defines,
        ],
    )
    args.add_all(
        all_defines,
        map_each = _exclude_swift_incompatible_define,
        format_each = "-D%s",
        uniquify = True,
    )

def _package_identifier_configurator(prerequisites, args):
    """Adds the package identifier to the action command line."""
    label = getattr(prerequisites, "target_label", None)
    if label:
        args.add("-package-name", label.package)

def _constant_value_extraction_configurator(prerequisites, args):
    """Adds flags related to constant value extraction to the command line."""
    if not prerequisites.const_gather_protocols_file:
        return None

    args.add("-emit-const-values")
    args.add_all(
        [
            "-const-gather-protocols-file",
            prerequisites.const_gather_protocols_file,
        ],
        before_each = "-Xfrontend",
    )
    return ConfigResultInfo(
        inputs = [prerequisites.const_gather_protocols_file],
    )

def _upcoming_and_experimental_features_configurator(prerequisites, args):
    """Adds upcoming and experimental features to the command line."""
    args.add_all(
        prerequisites.upcoming_features,
        before_each = "-enable-upcoming-feature",
    )
    args.add_all(
        prerequisites.experimental_features,
        before_each = "-enable-experimental-feature",
    )

def _warnings_as_errors_configurator(prerequisites, args):
    """Adds upcoming and experimental features to the command line."""
    args.add_all(
        prerequisites.warnings_as_errors,
        format_each = "-Xwrapped-swift=-warning-as-error=%s",
    )

def _additional_inputs_configurator(prerequisites, _args):
    """Propagates additional input files to the action.

    This configurator does not add any flags to the command line, but ensures
    that any additional input files requested by the caller of the action are
    available in the sandbox.
    """
    return ConfigResultInfo(
        inputs = prerequisites.additional_inputs,
    )

# Swift compiler flags that should be banned (in either `copts` on a target or
# by passing `--swiftcopt` on the command line) should be listed here.
_BANNED_SWIFTCOPTS = {
}

def _fail_if_flag_is_banned(copt):
    """Fails the build if the given compiler flag matches a banned flag.

    This is meant to be used as a `map_each` argument to `args.add_all`,
    delaying the check until the action is actually executed and allowing it to
    happen during the building of the command line (when the flags are already
    being iterated), instead of doing a less-efficient separate traversal of the
    list earlier at analysis time.

    Args:
        copt: The flag to check.

    Returns:
        The original flag, if the function didn't fail.
    """
    reason = _BANNED_SWIFTCOPTS.get(copt)
    if reason:
        fail("The Swift compiler flag '{}' may not be used. {}".format(
            copt,
            reason,
        ))
    return copt

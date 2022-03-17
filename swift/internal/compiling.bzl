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

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:types.bzl", "types")
load(
    ":actions.bzl",
    "is_action_enabled",
    "run_toolchain_action",
    "swift_action_names",
)
load(":debugging.bzl", "should_embed_swiftmodule_for_debugging")
load(":derived_files.bzl", "derived_files")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_BITCODE_EMBEDDED",
    "SWIFT_FEATURE_CACHEABLE_SWIFTMODULES",
    "SWIFT_FEATURE_COVERAGE",
    "SWIFT_FEATURE_COVERAGE_PREFIX_MAP",
    "SWIFT_FEATURE_DBG",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_DISABLE_SYSTEM_INDEX",
    "SWIFT_FEATURE_EMIT_BC",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_ENABLE_SKIP_FUNCTION_BODIES",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_FASTBUILD",
    "SWIFT_FEATURE_FULL_DEBUG_INFO",
    "SWIFT_FEATURE_GLOBAL_MODULE_CACHE_USES_TMPDIR",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_LAYERING_CHECK",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_ASAN_VERSION_CHECK",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_OSIZE",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_REWRITE_GENERATED_HEADER",
    "SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION",
    "SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_SUPPORTS_SYSTEM_MODULE_FLAG",
    "SWIFT_FEATURE_SYSTEM_MODULE",
    "SWIFT_FEATURE_USE_C_MODULES",
    "SWIFT_FEATURE_USE_GLOBAL_INDEX_STORE",
    "SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE",
    "SWIFT_FEATURE_USE_OLD_DRIVER",
    "SWIFT_FEATURE_USE_PCH_OUTPUT_DIR",
    "SWIFT_FEATURE_VFSOVERLAY",
    "SWIFT_FEATURE__NUM_THREADS_0_IN_SWIFTCOPTS",
    "SWIFT_FEATURE__WMO_IN_SWIFTCOPTS",
)
load(
    ":features.bzl",
    "are_all_features_enabled",
    "get_cc_feature_configuration",
    "is_feature_enabled",
)
load(":module_maps.bzl", "write_module_map")
load(
    ":providers.bzl",
    "SwiftInfo",
    "create_clang_module",
    "create_module",
    "create_swift_info",
    "create_swift_module",
)
load(":toolchain_config.bzl", "swift_toolchain_config")
load(
    ":utils.bzl",
    "compact",
    "compilation_context_for_explicit_module_compilation",
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

# Swift command line flags that enable whole module optimization. (This
# dictionary is used as a set for quick lookup; the values are irrelevant.)
_WMO_FLAGS = {
    "-wmo": True,
    "-whole-module-optimization": True,
    "-force-single-frontend-invocation": True,
}

def compile_action_configs(
        *,
        additional_objc_copts = [],
        additional_swiftc_copts = [],
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
        generated_header_rewriter: An executable that will be invoked after
            compilation to rewrite the generated header, or None if this is not
            desired.

    Returns:
        The list of action configs needed to perform compilation.
    """

    #### Flags that control the driver
    action_configs = [
        # Use the legacy driver if requested.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-disallow-use-new-driver"),
            ],
            features = [SWIFT_FEATURE_USE_OLD_DRIVER],
        ),
    ]

    #### Flags that control compilation outputs
    action_configs += [
        # Emit object file(s).
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-emit-object"),
            ],
            not_features = [SWIFT_FEATURE_EMIT_BC],
        ),

        # Emit llvm bc file(s).
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-emit-bc"),
            ],
            features = [SWIFT_FEATURE_EMIT_BC],
        ),

        # Add the single object file or object file map, whichever is needed.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_output_object_or_file_map_configurator],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.DERIVE_FILES],
            configurators = [_output_swiftmodule_or_file_map_configurator],
        ),

        # Dump ast files
        swift_toolchain_config.action_config(
            actions = [swift_action_names.DUMP_AST],
            configurators = [
                swift_toolchain_config.add_arg("-dump-ast"),
                swift_toolchain_config.add_arg("-suppress-warnings"),
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.DUMP_AST],
            configurators = [_output_ast_path_or_file_map_configurator],
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

        # Don't embed Clang module breadcrumbs in debug info.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xfrontend",
                    "-no-clang-module-breadcrumbs",
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
            not_features = [SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.DERIVE_FILES],
            configurators = [_emit_module_path_configurator],
        ),

        # Configure library evolution and the path to the .swiftinterface file.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-enable-library-evolution"),
            ],
            features = [
                SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION,
                SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION,
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [_emit_module_interface_path_configurator],
            features = [
                SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION,
                SWIFT_FEATURE_EMIT_SWIFTINTERFACE,
            ],
        ),

        # Configure the path to the emitted *-Swift.h file.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_emit_objc_header_path_configurator],
            not_features = [
                SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION,
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.DERIVE_FILES],
            configurators = [_emit_objc_header_path_configurator],
        ),
    ]

    if generated_header_rewriter:
        # Only add the generated header rewriter to the command line only if the
        # toolchain provides one, the relevant feature is requested, and the
        # particular compilation action is generating a header.
        def generated_header_rewriter_configurator(prerequisites, args):
            if prerequisites.generated_header_file:
                args.add(
                    generated_header_rewriter,
                    format = "-Xwrapped-swift=-generated-header-rewriter=%s",
                )

        action_configs.append(
            swift_toolchain_config.action_config(
                actions = [swift_action_names.COMPILE],
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
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-DDEBUG"),
            ],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FASTBUILD]],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-DNDEBUG"),
            ],
            features = [SWIFT_FEATURE_OPT],
        ),

        # Set the optimization mode. For dbg/fastbuild, use `-O0`. For opt, use
        # `-O` unless the `swift.opt_uses_osize` feature is enabled, then use
        # `-Osize`.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-Onone"),
            ],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FASTBUILD]],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-O"),
            ],
            features = [SWIFT_FEATURE_OPT],
            not_features = [SWIFT_FEATURE_OPT_USES_OSIZE],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-Osize"),
            ],
            features = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_OSIZE],
        ),

        # If the `swift.opt_uses_wmo` feature is enabled, opt builds should also
        # automatically imply whole-module optimization.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-whole-module-optimization"),
            ],
            features = [
                [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
                [SWIFT_FEATURE__WMO_IN_SWIFTCOPTS],
            ],
        ),

        # Enable or disable serialization of debugging options into
        # swiftmodules.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xfrontend",
                    "-no-serialize-debugging-options",
                ),
            ],
            features = [SWIFT_FEATURE_CACHEABLE_SWIFTMODULES],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
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
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
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
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [swift_toolchain_config.add_arg("-g")],
            features = [[SWIFT_FEATURE_DBG], [SWIFT_FEATURE_FULL_DEBUG_INFO]],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-gline-tables-only"),
            ],
            features = [SWIFT_FEATURE_FASTBUILD],
            not_features = [SWIFT_FEATURE_FULL_DEBUG_INFO],
        ),

        # Make paths written into debug info workspace-relative.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
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

        # Make paths written into coverage info workspace-relative.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xwrapped-swift=-coverage-prefix-pwd-is-dot",
                ),
            ],
            features = [
                [SWIFT_FEATURE_COVERAGE_PREFIX_MAP, SWIFT_FEATURE_COVERAGE],
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
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-profile-generate"),
                swift_toolchain_config.add_arg("-profile-coverage-mapping"),
            ],
            features = [SWIFT_FEATURE_COVERAGE],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-sanitize=address"),
            ],
            features = ["asan"],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xllvm",
                    "-asan-guard-against-version-mismatch=0",
                ),
            ],
            features = [
                "asan",
                SWIFT_FEATURE_NO_ASAN_VERSION_CHECK,
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-sanitize=thread"),
            ],
            features = ["tsan"],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-sanitize=undefined"),
            ],
            features = ["ubsan"],
        ),
    ]

    #### Flags controlling how Swift/Clang modular inputs are processed

    action_configs += [
        # Treat paths in .modulemap files as workspace-relative, not modulemap-
        # relative.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
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
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_global_module_cache_configurator],
            features = [SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE],
            not_features = [
                [SWIFT_FEATURE_USE_C_MODULES],
                [SWIFT_FEATURE_GLOBAL_MODULE_CACHE_USES_TMPDIR],
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_tmpdir_module_cache_configurator],
            features = [
                SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE,
                SWIFT_FEATURE_GLOBAL_MODULE_CACHE_USES_TMPDIR,
            ],
            not_features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xwrapped-swift=-ephemeral-module-cache",
                ),
            ],
            not_features = [
                [SWIFT_FEATURE_USE_C_MODULES],
                [SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE],
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_pch_output_dir_configurator],
            features = [
                SWIFT_FEATURE_USE_PCH_OUTPUT_DIR,
            ],
        ),

        # When using C modules, disable the implicit search for module map files
        # because all of them, including system dependencies, will be provided
        # explicitly.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
            ],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xcc",
                    "-fno-implicit-module-maps",
                ),
            ],
            features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        # Do not allow implicit modules to be used at all when emitting an
        # explicit C/Objective-C module. Consider the case of two modules A and
        # B, where A depends on B. If B does not emit an explicit module, then
        # when A is compiled it would contain a hardcoded reference to B via its
        # path in the implicit module cache. Thus, A would not be movable; some
        # library importing A would try to resolve B at that path, which may no
        # longer exist when the upstream library is built.
        #
        # This implies that for a C/Objective-C library to build as an explicit
        # module, all of its dependencies must as well. On the other hand, a
        # Swift library can be compiled with some of its Objective-C
        # dependencies still using implicit modules, as long as no Objective-C
        # library wants to import that Swift library's generated header and
        # build itself as an explicit module.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.PRECOMPILE_C_MODULE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xcc",
                    "-fno-implicit-modules",
                ),
            ],
            features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.PRECOMPILE_C_MODULE],
            configurators = [_c_layering_check_configurator],
            features = [SWIFT_FEATURE_LAYERING_CHECK],
            not_features = [SWIFT_FEATURE_SYSTEM_MODULE],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.PRECOMPILE_C_MODULE],
            configurators = [
                # Before Swift 5.4, ClangImporter doesn't currently handle the
                # IsSystem bit correctly for the input file and ignores the
                # `-fsystem-module` flag, which causes the module map to be
                # treated as a user input. We can work around this by disabling
                # diagnostics for system modules. However, this also disables
                # behavior in ClangImporter that causes system APIs that use
                # `UInt` to be imported to use `Int` instead. The only solution
                # here is to use Xcode 12.5 or higher.
                swift_toolchain_config.add_arg("-Xcc", "-w"),
                swift_toolchain_config.add_arg(
                    "-Xcc",
                    "-Wno-nullability-declspec",
                ),
            ],
            features = [SWIFT_FEATURE_SYSTEM_MODULE],
            not_features = [SWIFT_FEATURE_SUPPORTS_SYSTEM_MODULE_FLAG],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.PRECOMPILE_C_MODULE],
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
                swift_toolchain_config.add_arg("-Xcc", "-Xclang"),
                swift_toolchain_config.add_arg("-Xcc", "-emit-module"),
                swift_toolchain_config.add_arg("-Xcc", "-Xclang"),
                swift_toolchain_config.add_arg("-Xcc", "-fsystem-module"),
            ],
            features = [
                SWIFT_FEATURE_SUPPORTS_SYSTEM_MODULE_FLAG,
                SWIFT_FEATURE_SYSTEM_MODULE,
            ],
        ),
    ]

    #### Search paths for Swift module dependencies
    action_configs.extend([
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_dependencies_swiftmodules_configurator],
            not_features = [SWIFT_FEATURE_VFSOVERLAY],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [
                _dependencies_swiftmodules_vfsoverlay_configurator,
            ],
            features = [SWIFT_FEATURE_VFSOVERLAY],
        ),
    ])

    #### Search paths for framework dependencies
    action_configs.extend([
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [
                lambda prereqs, args: _framework_search_paths_configurator(
                    prereqs,
                    args,
                    is_swift = True,
                ),
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.PRECOMPILE_C_MODULE],
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
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
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
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_dependencies_clang_modules_configurator],
            features = [SWIFT_FEATURE_USE_C_MODULES],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
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
                swift_action_names.DERIVE_FILES,
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
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
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
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                partial.make(
                    _wmo_thread_count_configurator,
                    # WMO is implied by features, so don't check the user
                    # compile flags.
                    False,
                ),
            ],
            features = [
                [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
                [SWIFT_FEATURE__WMO_IN_SWIFTCOPTS],
            ],
            not_features = [SWIFT_FEATURE__NUM_THREADS_0_IN_SWIFTCOPTS],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                partial.make(
                    _wmo_thread_count_configurator,
                    # WMO is not implied by features, so check the user compile
                    # flags in case they enabled it there.
                    True,
                ),
            ],
            not_features = [
                [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
                [SWIFT_FEATURE__NUM_THREADS_0_IN_SWIFTCOPTS],
            ],
        ),

        # Set the module name.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_module_name_configurator],
        ),

        # Pass extra flags for swiftmodule only compilations
        swift_toolchain_config.action_config(
            actions = [swift_action_names.DERIVE_FILES],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-experimental-skip-non-inlinable-function-bodies",
                ),
            ],
            features = [SWIFT_FEATURE_ENABLE_SKIP_FUNCTION_BODIES],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_global_index_store_configurator],
            features = [
                SWIFT_FEATURE_INDEX_WHILE_BUILDING,
                SWIFT_FEATURE_USE_GLOBAL_INDEX_STORE,
            ],
        ),

        # Configure index-while-building.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [_index_while_building_configurator],
            features = [SWIFT_FEATURE_INDEX_WHILE_BUILDING],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-index-ignore-system-modules",
                ),
            ],
            features = [
                SWIFT_FEATURE_INDEX_WHILE_BUILDING,
                SWIFT_FEATURE_DISABLE_SYSTEM_INDEX,
            ],
        ),

        # User-defined conditional compilation flags (defined for Swift; those
        # passed directly to ClangImporter are handled above).
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_conditional_compilation_flag_configurator],
        ),
    ]

    # NOTE: The positions of these action configs in the list are important,
    # because it places the `copts` attribute ("user compile flags") after flags
    # added by the rules, and then the "additional objc" and "additional swift"
    # flags follow those, which are `--objccopt` and `--swiftcopt` flags from
    # the command line that should override even the flags specified in the
    # `copts` attribute.
    action_configs.append(
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_user_compile_flags_configurator],
        ),
    )
    if additional_objc_copts:
        action_configs.append(
            swift_toolchain_config.action_config(
                actions = [
                    swift_action_names.COMPILE,
                    swift_action_names.DERIVE_FILES,
                    swift_action_names.PRECOMPILE_C_MODULE,
                    swift_action_names.DUMP_AST,
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
            swift_toolchain_config.action_config(
                # TODO(allevato): Determine if there are any uses of
                # `-Xcc`-prefixed flags that need to be added to explicit module
                # actions, or if we should advise against/forbid that.
                actions = [
                    swift_action_names.COMPILE,
                    swift_action_names.DERIVE_FILES,
                    swift_action_names.DUMP_AST,
                ],
                configurators = [
                    lambda _, args: args.add_all(additional_swiftc_copts),
                ],
            ),
        )

    action_configs.append(
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_source_files_configurator],
        ),
    )

    # Add additional input files to the sandbox (does not modify flags).
    action_configs.append(
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.DUMP_AST,
            ],
            configurators = [_additional_inputs_configurator],
        ),
    )

    return action_configs

def _output_or_file_map(output_file_map, outputs, args):
    """Adds the output file map or single file to the command line."""
    if output_file_map:
        args.add("-output-file-map", output_file_map)
        return swift_toolchain_config.config_result(
            inputs = [output_file_map],
        )

    if len(outputs) != 1:
        fail(
            "Internal error: If not using an output file map, there should " +
            "only be a single object file expected as the output, but we " +
            "found: {}".format(outputs),
        )

    args.add("-o", outputs[0])
    return None

def _output_object_or_file_map_configurator(prerequisites, args):
    """Adds the output file map or single object file to the command line."""
    return _output_or_file_map(
        output_file_map = prerequisites.output_file_map,
        outputs = prerequisites.object_files,
        args = args,
    )

def _output_swiftmodule_or_file_map_configurator(prerequisites, args):
    """Adds the output file map or single object file to the command line."""
    return _output_or_file_map(
        output_file_map = prerequisites.derived_files_output_file_map,
        outputs = [prerequisites.swiftmodule_file],
        args = args,
    )

def _output_ast_path_or_file_map_configurator(prerequisites, args):
    """Adds the output file map or single AST file to the command line."""
    return _output_or_file_map(
        output_file_map = prerequisites.output_file_map,
        outputs = prerequisites.ast_files,
        args = args,
    )

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

def _tmpdir_module_cache_configurator(prerequisites, args):
    """Adds flags to enable a stable tmp directory module cache."""

    args.add(
        "-module-cache-path",
        paths.join(
            "/tmp/__build_bazel_rules_swift",
            "swift_module_cache",
            prerequisites.workspace_name,
        ),
    )

def _batch_mode_configurator(prerequisites, args):
    """Adds flags to enable batch compilation mode."""
    if not _is_wmo_manually_requested(prerequisites.user_compile_flags):
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
        depset(transitive = [
            prerequisites.cc_compilation_context.includes,
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
                prerequisites.cc_compilation_context.quote_includes,
            ],
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
        cc_compilation_context,
        is_swift,
        modules,
        objc_info,
        prefer_precompiled_modules):
    """Collects Clang module-related inputs to pass to an action.

    Args:
        cc_compilation_context: The `CcCompilationContext` of the target being
            compiled. The direct headers of this provider will be collected as
            inputs.
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
    direct_inputs = []
    transitive_inputs = []

    if cc_compilation_context:
        # The headers stored in the compilation context differ depending on the
        # kind of action we're invoking:
        if (is_swift and not prefer_precompiled_modules) or not is_swift:
            # If this is a `SwiftCompile` with explicit modules disabled, the
            # `headers` field is an already-computed set of the transitive
            # headers of all the deps. (For an explicit module build, we skip it
            # and will more selectively pick subsets for any individual modules
            # that need to fallback to implicit modules in the loop below).
            #
            # If this is a `SwiftPrecompileCModule`, then by definition we're
            # only here in a build with explicit modules enabled. We should only
            # need the direct headers of the module being compiled and its
            # direct dependencies (the latter because Clang needs them present
            # on the file system to map them to the module that contains them.)
            # However, we may also need some of the transitive headers, if the
            # module has dependencies that aren't recognized as modules (e.g.,
            # `cc_library` targets without the `swift_module` tag) and the
            # module's headers include those. This will likely over-estimate the
            # needed inputs, but we can't do better without include scanning in
            # Starlark.
            transitive_inputs.append(cc_compilation_context.headers)

    # Some rules still use the `umbrella_header` field to propagate a header
    # that they don't also include in `cc_compilation_context.headers`, so we
    # also need to pull these in for the time being.
    # TODO(b/142867898): This can be removed once the Swift rules start
    # generating its own module map for these targets.
    if objc_info:
        transitive_inputs.append(objc_info.umbrella_header)

    for module in modules:
        clang_module = module.clang

        # Add the module map, which we use for both implicit and explicit module
        # builds.
        module_map = clang_module.module_map
        if not module.is_system and type(module_map) == "File":
            direct_inputs.append(module_map)

        if prefer_precompiled_modules:
            precompiled_module = clang_module.precompiled_module
            if precompiled_module:
                # For builds preferring explicit modules, use it if we have it
                # and don't include any headers as inputs.
                direct_inputs.append(precompiled_module)
            else:
                # If we don't have an explicit module, we need the transitive
                # headers from the compilation context associated with the
                # module. This will likely overestimate the headers that will
                # actually be used in the action, but until we can use include
                # scanning from Starlark, we can't compute a more precise input
                # set.
                transitive_inputs.append(
                    clang_module.compilation_context.headers,
                )

    return swift_toolchain_config.config_result(
        inputs = direct_inputs,
        transitive_inputs = transitive_inputs,
    )

def _clang_modulemap_dependency_args(module, ignore_system = True):
    """Returns a `swiftc` argument for the module map of a Clang module.

    Args:
        module: A struct containing information about the module, as defined by
            `swift_common.create_module`.
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
            `swift_common.create_module`.

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

    return _collect_clang_module_inputs(
        cc_compilation_context = prerequisites.cc_compilation_context,
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

    # Uniquify the arguments because different modules might be defined in the
    # same module map file, so it only needs to be present once on the command
    # line.
    args.add_all(
        modules,
        before_each = "-Xcc",
        map_each = _clang_module_dependency_args,
        uniquify = True,
    )

    return _collect_clang_module_inputs(
        cc_compilation_context = prerequisites.cc_compilation_context,
        is_swift = prerequisites.is_swift,
        modules = modules,
        objc_info = prerequisites.objc_info,
        prefer_precompiled_modules = True,
    )

def _framework_search_paths_configurator(prerequisites, args, is_swift):
    """Add search paths for prebuilt frameworks to the command line."""

    # Swift doesn't automatically propagate its `-F` flag to ClangImporter, so
    # we add it manually with `-Xcc` below (for both regular compilations, in
    # case they're using implicit modules, and Clang module compilations). We
    # don't need to add regular `-F` if this is a Clang module compilation,
    # though, since it won't be used.
    if is_swift:
        args.add_all(
            prerequisites.cc_compilation_context.framework_includes,
            format_each = "-F%s",
        )
    args.add_all(
        prerequisites.cc_compilation_context.framework_includes,
        format_each = "-F%s",
        before_each = "-Xcc",
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

def _source_files_configurator(prerequisites, args):
    """Adds source files to the command line and required inputs."""
    args.add_all(prerequisites.source_files)

    # Only add source files to the input file set if they are not strings (for
    # example, the module map of a system framework will be passed in as a file
    # path relative to the SDK root, not as a `File` object).
    return swift_toolchain_config.config_result(
        inputs = [
            source_file
            for source_file in prerequisites.source_files
            if not types.is_string(source_file)
        ],
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
    for copt in user_compile_flags:
        if copt in _WMO_FLAGS:
            return True
    return False

def features_from_swiftcopts(swiftcopts):
    """Returns a list of features to enable based on `--swiftcopt` flags.

    Since `--swiftcopt` flags are hooked into the action configuration when the
    toolchain is configured, it's not possible for individual actions to query
    them easily if those flags may determine the nature of outputs (for example,
    single- vs. multi-threaded WMO). The toolchain can call this function to map
    those flags to private features that can be queried instead.

    Args:
        swiftcopts: The list of command line flags that were passed using
            `--swiftcopt`.

    Returns:
        A list (possibly empty) of strings denoting feature names that should be
        enabled on the toolchain.
    """
    features = []
    if _is_wmo_manually_requested(user_compile_flags = swiftcopts):
        features.append(SWIFT_FEATURE__WMO_IN_SWIFTCOPTS)
    if _find_num_threads_flag_value(user_compile_flags = swiftcopts) == 0:
        features.append(SWIFT_FEATURE__NUM_THREADS_0_IN_SWIFTCOPTS)
    return features

def _index_while_building_configurator(prerequisites, args):
    """Adds flags for index-store generation to the command line."""
    if not _index_store_path_overridden(prerequisites.user_compile_flags):
        args.add("-index-store-path", prerequisites.indexstore_directory.path)

def _pch_output_dir_configurator(prerequisites, args):
    """Adds flags for pch-output-dir configuration to the command line.

      This is a directory to persist automatically created precompiled bridging headers

      Note: that like the global index store and module cache, we expect clang
      to namespace these correctly per arch / os version / etc by the hash in
      the path. However, it is also put into the bin_dir for an added layer of
      safety.
    """
    args.add(
        "-pch-output-dir",
        paths.join(prerequisites.bin_dir.path, "_pch_output_dir"),
    )

def _global_index_store_configurator(prerequisites, args):
    """Adds flags for index-store generation to the command line."""
    out_dir = prerequisites.indexstore_directory.dirname.split("/")[0]
    path = out_dir + "/_global_index_store"
    args.add("-Xwrapped-swift=-global-index-store-import-path=" + path)

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
    )

def _additional_inputs_configurator(prerequisites, _args):
    """Propagates additional input files to the action.

    This configurator does not add any flags to the command line, but ensures
    that any additional input files requested by the caller of the action are
    available in the sandbox.
    """
    return swift_toolchain_config.config_result(
        inputs = prerequisites.additional_inputs,
    )

def _module_name_safe(string):
    """Returns a transformation of `string` that is safe for module names."""
    result = ""
    saw_non_identifier_char = False
    for ch in string.elems():
        if ch.isalnum() or ch == "_":
            # If we're seeing an identifier character after a sequence of
            # non-identifier characters, append an underscore and reset our
            # tracking state before appending the identifier character.
            if saw_non_identifier_char:
                result += "_"
                saw_non_identifier_char = False
            result += ch
        elif result:
            # Only track this if `result` has content; this ensures that we
            # (intentionally) drop leading non-identifier characters instead of
            # adding a leading underscore.
            saw_non_identifier_char = True

    return result

def derive_module_name(*args):
    """Returns a derived module name from the given build label.

    For targets whose module name is not explicitly specified, the module name
    is computed using the following algorithm:

    *   The package and name components of the label are considered separately.
        All _interior_ sequences of non-identifier characters (anything other
        than `a-z`, `A-Z`, `0-9`, and `_`) are replaced by a single underscore
        (`_`). Any leading or trailing non-identifier characters are dropped.
    *   If the package component is non-empty after the above transformation,
        it is joined with the transformed name component using an underscore.
        Otherwise, the transformed name is used by itself.
    *   If this would result in a string that begins with a digit (`0-9`), an
        underscore is prepended to make it identifier-safe.

    This mapping is intended to be fairly predictable, but not reversible.

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

    package_part = _module_name_safe(package.lstrip("//"))
    name_part = _module_name_safe(name)
    if package_part:
        module_name = package_part + "_" + name_part
    else:
        module_name = name_part
    if module_name[0].isdigit():
        module_name = "_" + module_name
    return module_name

def compile(
        *,
        actions,
        additional_inputs = [],
        copts = [],
        defines = [],
        deps = [],
        feature_configuration,
        generated_header_name = None,
        module_name,
        private_deps = [],
        srcs,
        swift_toolchain,
        target_name,
        workspace_name):
    """Compiles a Swift module.

    Args:
        actions: The context's `actions` object.
        additional_inputs: A list of `File`s representing additional input files
            that need to be passed to the Swift compile action because they are
            referenced by compiler flags.
        copts: A list of compiler flags that apply to the target being built.
            These flags, along with those from Bazel's Swift configuration
            fragment (i.e., `--swiftcopt` command line flags) are scanned to
            determine whether whole module optimization is being requested,
            which affects the nature of the output files.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        deps: Non-private dependencies of the target being compiled. These
            targets are used as dependencies of both the Swift module being
            compiled and the Clang module for the generated header. These
            targets must propagate one of the following providers: `CcInfo`,
            `SwiftInfo`, or `apple_common.Objc`.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        generated_header_name: The name of the Objective-C generated header that
            should be generated for this module. If omitted, no header will be
            generated.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `swift_common.derive_module_name` to generate
            a default from the target's label if needed.
        private_deps: Private (implementation-only) dependencies of the target
            being compiled. These are only used as dependencies of the Swift
            module, not of the Clang module for the generated header. These
            targets must propagate one of the following providers: `CcInfo`,
            `SwiftInfo`, or `apple_common.Objc`.
        srcs: The Swift source files to compile.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        workspace_name: The name of the workspace for which the code is being
             compiled, which is used to determine unique file paths for some
             outputs.

    Returns:
        A tuple containing three elements:

        1.  A Swift module context (as returned by `swift_common.create_module`)
            that contains the Swift (and potentially C/Objective-C) compilation
            prerequisites of the compiled module. This should typically be
            propagated by a `SwiftInfo` provider of the calling rule.
        2.  A `CcCompilationOutputs` object (as returned by
            `cc_common.create_compilation_outputs`) that contains the compiled
            object files.
        3.  A struct containing:
            *   `ast_files`: A list of `File`s output from the `DUMP_AST`
                action.
            *   `indexstore`: A `File` representing the directory that contains
                the index store data generated by the compiler if
                index-while-building is enabled. May be None if no indexing was
                requested.
    """

    # Collect the `SwiftInfo` providers that represent the dependencies of the
    # Objective-C generated header module -- this includes the dependencies of
    # the Swift module, plus any additional dependencies that the toolchain says
    # are required for all generated header modules. These are used immediately
    # below to write the module map for the header's module (to provide the
    # `use` declarations), and later in this function when precompiling the
    # module.
    generated_module_deps_swift_infos = (
        get_providers(deps, SwiftInfo) +
        swift_toolchain.generated_header_module_implicit_deps_providers.swift_infos
    )

    compile_outputs, other_outputs = _declare_compile_outputs(
        srcs = srcs,
        actions = actions,
        feature_configuration = feature_configuration,
        generated_header_name = generated_header_name,
        generated_module_deps_swift_infos = generated_module_deps_swift_infos,
        module_name = module_name,
        target_name = target_name,
        user_compile_flags = copts,
    )

    split_derived_file_generation = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION,
    )

    if split_derived_file_generation:
        all_compile_outputs = compact([
            compile_outputs.swiftinterface_file,
            compile_outputs.indexstore_directory,
        ]) + compile_outputs.object_files
        all_derived_outputs = compact([
            # The `.swiftmodule` file is explicitly listed as the first output
            # because it will always exist and because Bazel uses it as a key for
            # various things (such as the filename prefix for param files generated
            # for that action). This guarantees some predictability.
            compile_outputs.swiftmodule_file,
            compile_outputs.swiftdoc_file,
            compile_outputs.swiftsourceinfo_file,
            compile_outputs.generated_header_file,
        ]) + other_outputs
    else:
        all_compile_outputs = compact([
            # The `.swiftmodule` file is explicitly listed as the first output
            # because it will always exist and because Bazel uses it as a key for
            # various things (such as the filename prefix for param files generated
            # for that action). This guarantees some predictability.
            compile_outputs.swiftmodule_file,
            compile_outputs.swiftdoc_file,
            compile_outputs.swiftinterface_file,
            compile_outputs.swiftsourceinfo_file,
            compile_outputs.generated_header_file,
            compile_outputs.indexstore_directory,
        ]) + compile_outputs.object_files + other_outputs
        all_derived_outputs = []

    # Merge the providers from our dependencies so that we have one each for
    # `SwiftInfo`, `CcInfo`, and `apple_common.Objc`. Then we can pass these
    # into the action prerequisites so that configurators have easy access to
    # the full set of values and inputs through a single accessor.
    merged_providers = _merge_targets_providers(
        implicit_deps_providers = swift_toolchain.implicit_deps_providers,
        targets = deps + private_deps,
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

    transitive_swiftmodules = []
    defines_set = sets.make(defines)
    for module in transitive_modules:
        swift_module = module.swift
        if not swift_module:
            continue
        transitive_swiftmodules.append(swift_module.swiftmodule)
        if swift_module.defines:
            defines_set = sets.union(
                defines_set,
                sets.make(swift_module.defines),
            )

    # We need this when generating the VFS overlay file and also when
    # configuring inputs for the compile action, so it's best to precompute it
    # here.
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
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_providers.cc_info.compilation_context,
        defines = sets.to_list(defines_set),
        genfiles_dir = feature_configuration._genfiles_dir,
        is_swift = True,
        module_name = module_name,
        objc_include_paths_workaround = (
            merged_providers.objc_include_paths_workaround
        ),
        objc_info = merged_providers.objc_info,
        source_files = srcs,
        transitive_modules = transitive_modules,
        transitive_swiftmodules = transitive_swiftmodules,
        user_compile_flags = copts,
        vfsoverlay_file = vfsoverlay_file,
        vfsoverlay_search_path = _SWIFTMODULES_VFS_ROOT,
        workspace_name = workspace_name,
        # Merge the compile outputs into the prerequisites.
        **struct_fields(compile_outputs)
    )

    if split_derived_file_generation:
        run_toolchain_action(
            actions = actions,
            action_name = swift_action_names.DERIVE_FILES,
            feature_configuration = feature_configuration,
            outputs = all_derived_outputs,
            prerequisites = prerequisites,
            progress_message = "Generating derived files for Swift module %{label}",
            swift_toolchain = swift_toolchain,
        )

    run_toolchain_action(
        actions = actions,
        action_name = swift_action_names.COMPILE,
        feature_configuration = feature_configuration,
        outputs = all_compile_outputs,
        prerequisites = prerequisites,
        progress_message = "Compiling Swift module %{label}",
        swift_toolchain = swift_toolchain,
    )

    # Dump AST has to run in its own action because `-dump-ast` is incompatible
    # with emitting dependency files, which compile/derive files use when
    # compiling via the worker.
    # Given usage of AST files is expected to be limited compared to other
    # compile outputs, moving generation off of the critical path is likely
    # a reasonable tradeoff for the additional action.
    run_toolchain_action(
        actions = actions,
        action_name = swift_action_names.DUMP_AST,
        feature_configuration = feature_configuration,
        outputs = compile_outputs.ast_files,
        prerequisites = prerequisites,
        progress_message = "Dumping Swift AST for %{label}",
        swift_toolchain = swift_toolchain,
    )

    # If a header and module map were generated for this Swift module, attempt
    # to precompile the explicit module for that header as well.
    if generated_header_name and not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_NO_GENERATED_MODULE_MAP,
    ):
        compilation_context_to_compile = (
            compilation_context_for_explicit_module_compilation(
                compilation_contexts = [cc_common.create_compilation_context(
                    headers = depset([compile_outputs.generated_header_file]),
                )],
                deps = deps,
            )
        )
        precompiled_module = _precompile_clang_module(
            actions = actions,
            cc_compilation_context = compilation_context_to_compile,
            feature_configuration = feature_configuration,
            is_swift_generated_header = True,
            module_map_file = compile_outputs.generated_module_map_file,
            module_name = module_name,
            swift_infos = generated_module_deps_swift_infos,
            swift_toolchain = swift_toolchain,
            target_name = target_name,
        )
    else:
        precompiled_module = None

    module_context = create_module(
        name = module_name,
        clang = create_clang_module(
            compilation_context = _create_cc_compilation_context(
                actions = actions,
                defines = defines,
                deps = deps,
                feature_configuration = feature_configuration,
                public_hdrs = compact([compile_outputs.generated_header_file]),
                swift_toolchain = swift_toolchain,
                target_name = target_name,
            ),
            module_map = compile_outputs.generated_module_map_file,
            precompiled_module = precompiled_module,
        ),
        is_system = False,
        swift = create_swift_module(
            defines = defines,
            swiftdoc = compile_outputs.swiftdoc_file,
            swiftinterface = compile_outputs.swiftinterface_file,
            swiftmodule = compile_outputs.swiftmodule_file,
            swiftsourceinfo = compile_outputs.swiftsourceinfo_file,
        ),
    )

    cc_compilation_outputs = cc_common.create_compilation_outputs(
        objects = depset(compile_outputs.object_files),
        pic_objects = depset(compile_outputs.object_files),
    )

    other_compilation_outputs = struct(
        ast_files = compile_outputs.ast_files,
        indexstore = compile_outputs.indexstore_directory,
    )

    return module_context, cc_compilation_outputs, other_compilation_outputs

def precompile_clang_module(
        *,
        actions,
        cc_compilation_context,
        feature_configuration,
        module_map_file,
        module_name,
        swift_toolchain,
        target_name,
        swift_infos = []):
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
        swift_infos: A list of `SwiftInfo` providers representing dependencies
            required to compile this module.

    Returns:
        A `File` representing the precompiled module (`.pcm`) file, or `None` if
        the toolchain or target does not support precompiled modules.
    """
    return _precompile_clang_module(
        actions = actions,
        cc_compilation_context = cc_compilation_context,
        feature_configuration = feature_configuration,
        is_swift_generated_header = False,
        module_map_file = module_map_file,
        module_name = module_name,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = target_name,
    )

def _precompile_clang_module(
        *,
        actions,
        cc_compilation_context,
        feature_configuration,
        is_swift_generated_header,
        module_map_file,
        module_name,
        swift_infos = [],
        swift_toolchain,
        target_name):
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
        is_swift_generated_header: If True, the action is compiling the
            Objective-C header generated by the Swift compiler for a module.
        module_map_file: A textual module map file that defines the Clang module
            to be compiled.
        module_name: The name of the top-level module in the module map that
            will be compiled.
        swift_infos: A list of `SwiftInfo` providers representing dependencies
            required to compile this module.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

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

    if not is_swift_generated_header:
        implicit_swift_infos = (
            swift_toolchain.clang_implicit_deps_providers.swift_infos
        )
        cc_compilation_context = cc_common.merge_cc_infos(
            cc_infos = swift_toolchain.clang_implicit_deps_providers.cc_infos,
            direct_cc_infos = [
                CcInfo(compilation_context = cc_compilation_context),
            ],
        ).compilation_context
    else:
        implicit_swift_infos = []

    if not is_swift_generated_header and implicit_swift_infos:
        swift_infos = list(swift_infos)
        swift_infos.extend(implicit_swift_infos)

    if swift_infos:
        merged_swift_info = create_swift_info(swift_infos = swift_infos)
        transitive_modules = merged_swift_info.transitive_modules.to_list()
    else:
        transitive_modules = []

    prerequisites = struct(
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = cc_compilation_context,
        genfiles_dir = feature_configuration._genfiles_dir,
        is_swift = False,
        is_swift_generated_header = is_swift_generated_header,
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
        progress_message = "Precompiling C module %{label}",
        swift_toolchain = swift_toolchain,
    )

    return precompiled_module

def _create_cc_compilation_context(
        *,
        actions,
        defines,
        deps,
        feature_configuration,
        public_hdrs,
        swift_toolchain,
        target_name):
    """Creates a `CcCompilationContext` to propagate for a Swift module.

    The returned compilation context contains the generated Objective-C header
    for the module (if any), along with any preprocessor defines based on
    compilation settings passed to the Swift compilation.

    Args:
        actions: The context's `actions` object.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        deps: Non-private dependencies of the target being compiled. These
            targets are used as dependencies of both the Swift module being
            compiled and the Clang module for the generated header. These
            targets must propagate one of the following providers: `CcInfo`,
            `SwiftInfo`, or `apple_common.Objc`.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        public_hdrs: Public headers that should be propagated by the new
            compilation context (for example, the module's generated header).
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

    Returns:
        The `CcCompilationContext` that should be propagated by the calling
        target.
    """

    # If we are propagating headers, call `cc_common.compile` to get the
    # compilation context instead of creating it directly. This gives the
    # C++/Objective-C logic in Bazel an opportunity to register its own actions
    # relevant to the headers, like creating a layering check module map.
    # Without this, Swift targets won't be treated as `use`d modules when
    # generating the layering check module map for an `objc_library`, and those
    # layering checks will fail when the Objective-C code tries to import the
    # `swift_library`'s headers.
    if public_hdrs:
        compilation_context, _ = cc_common.compile(
            actions = actions,
            cc_toolchain = swift_toolchain.cc_toolchain_info,
            compilation_contexts = [
                dep[CcInfo].compilation_context
                for dep in deps
                if CcInfo in dep
            ],
            defines = defines,
            feature_configuration = get_cc_feature_configuration(
                feature_configuration = feature_configuration,
            ),
            name = target_name,
            public_hdrs = public_hdrs,
        )
        return compilation_context

    # If there were no headers, create the compilation context manually. This
    # avoids having Bazel create an action that results in an empty module map
    # that won't contribute meaningfully to layering checks anyway.
    if defines:
        direct_cc_infos = [
            CcInfo(compilation_context = cc_common.create_compilation_context(
                defines = depset(defines),
            )),
        ]
    else:
        direct_cc_infos = []

    return cc_common.merge_cc_infos(
        cc_infos = [dep[CcInfo] for dep in deps if CcInfo in dep],
        direct_cc_infos = direct_cc_infos,
    ).compilation_context

def _declare_compile_outputs(
        *,
        actions,
        feature_configuration,
        generated_header_name,
        generated_module_deps_swift_infos,
        module_name,
        srcs,
        target_name,
        user_compile_flags):
    """Declares output files and optional output file map for a compile action.

    Args:
        actions: The object used to register actions.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        generated_header_name: The desired name of the generated header for this
            module, or `None` if no header should be generated.
        generated_module_deps_swift_infos: `SwiftInfo` providers from
            dependencies of the module for the generated header of the target
            being compiled.
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
    swiftsourceinfo_file = derived_files.swiftsourceinfo(
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

    # If requested, generate the Swift header for this library so that it can be
    # included by Objective-C code that depends on it.
    if generated_header_name:
        generated_header = _declare_validated_generated_header(
            actions = actions,
            generated_header_name = generated_header_name,
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
        # Collect the names of Clang modules that the module being built
        # directly depends on.
        dependent_module_names = sets.make()
        for swift_info in generated_module_deps_swift_infos:
            for module in swift_info.direct_modules:
                if module.clang:
                    sets.insert(dependent_module_names, module.name)

        generated_module_map = derived_files.module_map(
            actions = actions,
            target_name = target_name,
        )
        write_module_map(
            actions = actions,
            dependent_module_names = sorted(
                sets.to_list(dependent_module_names),
            ),
            module_map_file = generated_module_map,
            module_name = module_name,
            public_headers = [generated_header],
        )
    else:
        generated_module_map = None

    # Now, declare outputs like object files for which there may be one or many,
    # depending on the compilation mode.
    output_nature = _emitted_output_nature(
        feature_configuration = feature_configuration,
        user_compile_flags = user_compile_flags,
    )

    # If enabled the compiler will emit LLVM BC files instead of Mach-O object
    # files.
    emits_bc = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_BC,
    )

    # If enabled the compiler will embed LLVM BC in the object files.
    embeds_bc = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_BITCODE_EMBEDDED,
    )

    if not output_nature.emits_multiple_objects:
        # If we're emitting a single object, we don't use an object map; we just
        # declare the output file that the compiler will generate and there are
        # no other partial outputs.
        object_files = [derived_files.whole_module_object_file(
            actions = actions,
            target_name = target_name,
        )]
        ast_files = [derived_files.ast(
            actions = actions,
            target_name = target_name,
            src = srcs[0],
        )]
        other_outputs = []
        output_file_map = None
        derived_files_output_file_map = None
    else:
        split_derived_file_generation = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION,
        )

        # Otherwise, we need to create an output map that lists the individual
        # object files so that we can pass them all to the archive action.
        output_info = _declare_multiple_outputs_and_write_output_file_map(
            actions = actions,
            embeds_bc = embeds_bc,
            emits_bc = emits_bc,
            split_derived_file_generation = split_derived_file_generation,
            srcs = srcs,
            target_name = target_name,
        )
        object_files = output_info.object_files
        ast_files = output_info.ast_files
        other_outputs = output_info.other_outputs
        output_file_map = output_info.output_file_map
        derived_files_output_file_map = output_info.derived_files_output_file_map

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
        ast_files = ast_files,
        generated_header_file = generated_header,
        generated_module_map_file = generated_module_map,
        indexstore_directory = indexstore_directory,
        object_files = object_files,
        output_file_map = output_file_map,
        derived_files_output_file_map = derived_files_output_file_map,
        swiftdoc_file = swiftdoc_file,
        swiftinterface_file = swiftinterface_file,
        swiftmodule_file = swiftmodule_file,
        swiftsourceinfo_file = swiftsourceinfo_file,
    )
    return compile_outputs, other_outputs

def _declare_multiple_outputs_and_write_output_file_map(
        actions,
        embeds_bc,
        emits_bc,
        split_derived_file_generation,
        srcs,
        target_name):
    """Declares low-level outputs and writes the output map for a compilation.

    Args:
        actions: The object used to register actions.
        embeds_bc: If `True` the compiler will embed LLVM BC in the object
            files.
        emits_bc: If `True` the compiler will generate LLVM BC files instead of
            object files.
        split_derived_file_generation: Whether objects and modules are produced
            by separate actions.
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
        *   `derived_files_output_file_map`: A `File` that represents the
            output file map that should be passed to derived file generation
            actions instead of the default `output_file_map` that is used for
            producing objects only.
    """
    output_map_file = derived_files.swiftc_output_file_map(
        actions = actions,
        target_name = target_name,
    )

    if split_derived_file_generation:
        derived_files_output_map_file = derived_files.swiftc_derived_output_file_map(
            actions = actions,
            target_name = target_name,
        )
    else:
        derived_files_output_map_file = None

    # The output map data, which is keyed by source path and will be written to
    # `output_map_file` and `derived_files_output_map_file`.
    output_map = {}
    derived_files_output_map = {}

    # Object files that will be used to build the archive.
    output_objs = []

    # Additional files, such as partial Swift modules, that must be declared as
    # action outputs although they are not processed further.
    other_outputs = []

    # AST files that are available in the swift_ast_file output group
    ast_files = []

    for src in srcs:
        src_output_map = {}

        if embeds_bc or emits_bc:
            # Declare the llvm bc file (there is one per source file).
            obj = derived_files.intermediate_bc_file(
                actions = actions,
                target_name = target_name,
                src = src,
            )
            (output_objs if emits_bc else other_outputs).append(obj)
            src_output_map["llvm-bc"] = obj.path

        if not emits_bc:
            # Declare the object file (there is one per source file).
            obj = derived_files.intermediate_object_file(
                actions = actions,
                target_name = target_name,
                src = src,
            )
            output_objs.append(obj)
            src_output_map["object"] = obj.path

        ast = derived_files.ast(
            actions = actions,
            target_name = target_name,
            src = src,
        )
        ast_files.append(ast)
        src_output_map["ast-dump"] = ast.path
        output_map[src.path] = struct(**src_output_map)

    actions.write(
        content = struct(**output_map).to_json(),
        output = output_map_file,
    )

    if split_derived_file_generation:
        actions.write(
            content = struct(**derived_files_output_map).to_json(),
            output = derived_files_output_map_file,
        )

    return struct(
        ast_files = ast_files,
        object_files = output_objs,
        other_outputs = other_outputs,
        output_file_map = output_map_file,
        derived_files_output_file_map = derived_files_output_map_file,
    )

def _declare_validated_generated_header(actions, generated_header_name):
    """Validates and declares the explicitly named generated header.

    If the file does not have a `.h` extension, the build will fail.

    Args:
        actions: The context's `actions` object.
        generated_header_name: The desired name of the generated header.

    Returns:
        A `File` that should be used as the output for the generated header.
    """
    extension = paths.split_extension(generated_header_name)[1]
    if extension != ".h":
        fail(
            "The generated header for a Swift module must have a '.h' " +
            "extension (got '{}').".format(generated_header_name),
        )

    return actions.declare_file(generated_header_name)

def _merge_targets_providers(implicit_deps_providers, targets):
    """Merges the compilation-related providers for the given targets.

    This function merges the `CcInfo`, `SwiftInfo`, and `apple_common.Objc`
    providers from the given targets into a single provider for each. These
    providers are then meant to be passed as prerequisites to compilation
    actions so that configurators can populate command lines and inputs based on
    their data.

    Args:
        implicit_deps_providers: The implicit deps providers `struct` from the
            Swift toolchain.
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
    cc_infos = list(implicit_deps_providers.cc_infos)
    objc_infos = list(implicit_deps_providers.objc_infos)
    swift_infos = list(implicit_deps_providers.swift_infos)

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
        if apple_common.Objc in target:
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

def new_objc_provider(
        *,
        additional_link_inputs = [],
        additional_objc_infos = [],
        alwayslink = False,
        deps,
        feature_configuration,
        libraries_to_link,
        module_context,
        user_link_flags = []):
    """Creates an `apple_common.Objc` provider for a Swift target.

    Args:
        additional_link_inputs: Additional linker input files that should be
            propagated to dependents.
        additional_objc_infos: Additional `apple_common.Objc` providers from
            transitive dependencies not provided by the `deps` argument.
        alwayslink: If True, any binary that depends on the providers returned
            by this function will link in all of the library's object files,
            even if some contain no symbols referenced by the binary.
        deps: The dependencies of the target being built, whose `Objc` providers
            will be passed to the new one in order to propagate the correct
            transitive fields.
        feature_configuration: The Swift feature configuration.
        libraries_to_link: A list (typically of one element) of the
            `LibraryToLink` objects from which the static archives (`.a` files)
            containing the target's compiled code will be retrieved.
        module_context: The module context as returned by
            `swift_common.compile`.
        user_link_flags: Linker options that should be propagated to dependents.

    Returns:
        An `apple_common.Objc` provider that should be returned by the calling
        rule.
    """

    # The link action registered by `apple_common.link_multi_arch_binary` only
    # looks at `Objc` providers, not `CcInfo`, for libraries to link.
    # Dependencies from an `objc_library` to a `cc_library` are handled as a
    # special case, but other `cc_library` dependencies (such as `swift_library`
    # to `cc_library`) would be lost since they do not receive the same
    # treatment. Until those special cases are resolved via the unification of
    # the Obj-C and C++ rules, we need to collect libraries from `CcInfo` and
    # put them into the new `Objc` provider.
    transitive_cc_libs = []
    for cc_info in get_providers(deps, CcInfo):
        static_libs = []
        for linker_input in cc_info.linking_context.linker_inputs.to_list():
            for library_to_link in linker_input.libraries:
                library = library_to_link.static_library
                if library:
                    static_libs.append(library)
        transitive_cc_libs.append(depset(static_libs, order = "topological"))

    direct_libraries = []
    force_load_libraries = []

    for library_to_link in libraries_to_link:
        library = library_to_link.static_library
        if library:
            direct_libraries.append(library)
            if alwayslink:
                force_load_libraries.append(library)

    if feature_configuration and should_embed_swiftmodule_for_debugging(
        feature_configuration = feature_configuration,
        module_context = module_context,
    ):
        module_file = module_context.swift.swiftmodule
        debug_link_flags = ["-Wl,-add_ast_path,{}".format(module_file.path)]
        debug_link_inputs = [module_file]
    else:
        debug_link_flags = []
        debug_link_inputs = []

    return apple_common.new_objc_provider(
        force_load_library = depset(
            force_load_libraries,
            order = "topological",
        ),
        library = depset(
            direct_libraries,
            transitive = transitive_cc_libs,
            order = "topological",
        ),
        link_inputs = depset(additional_link_inputs + debug_link_inputs),
        linkopt = depset(user_link_flags + debug_link_flags),
        providers = get_providers(
            deps,
            apple_common.Objc,
        ) + additional_objc_infos,
    )

def output_groups_from_other_compilation_outputs(*, other_compilation_outputs):
    """Returns a dictionary of output groups from a Swift module context.

    Args:
        other_compilation_outputs: The value in the third element of the tuple
            returned by `swift_common.compile`.

    Returns:
        A `dict` whose keys are the names of output groups and values are
        `depset`s of `File`s, which can be splatted as keyword arguments to the
        `OutputGroupInfo` constructor.
    """
    output_groups = {}

    if other_compilation_outputs.ast_files:
        output_groups["swift_ast_file"] = depset(
            other_compilation_outputs.ast_files,
        )

    if other_compilation_outputs.indexstore:
        output_groups["swift_index_store"] = depset([
            other_compilation_outputs.indexstore,
        ])

    return output_groups

def swift_library_output_map(name):
    """Returns the dictionary of implicit outputs for a `swift_library`.

    This function is used to specify the `outputs` of the `swift_library` rule;
    as such, its arguments must be named exactly the same as the attributes to
    which they refer.

    Args:
        name: The name of the target being built.

    Returns:
        The implicit outputs dictionary for a `swift_library`.
    """
    return {
        "archive": "lib{}.a".format(name),
    }

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

def _find_num_threads_flag_value(user_compile_flags):
    """Finds the value of the `-num-threads` flag.

    This function looks for the `-num-threads` flag and returns the
    corresponding value if found. If the flag is present multiple times, the
    last value is the one returned.

    Args:
        user_compile_flags: The options passed into the compile action.

    Returns:
        The numeric value of the `-num-threads` flag if found, otherwise `None`.
    """
    num_threads = None
    saw_num_threads = False
    for copt in user_compile_flags:
        if saw_num_threads:
            saw_num_threads = False
            num_threads = _safe_int(copt)
        elif copt == "-num-threads":
            saw_num_threads = True
    return num_threads

def _emitted_output_nature(feature_configuration, user_compile_flags):
    """Returns information about the nature of emitted compilation outputs.

    The compiler emits a single object if it is invoked with whole-module
    optimization enabled and is single-threaded (`-num-threads` is not present
    or is equal to 1); otherwise, it emits one object file per source file. It
    also emits a single `.swiftmodule` file for WMO builds, _regardless of
    thread count,_ so we have to treat that case separately.

    Args:
        feature_configuration: The feature configuration for the current
            compilation.
        user_compile_flags: The options passed into the compile action.

    Returns:
        A struct containing the following fields:

        *   `emits_multiple_objects`: `True` if the Swift frontend emits an
            object file per source file, instead of a single object file for the
            whole module, in a compilation action with the given flags.
    """
    is_wmo = (
        is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE__WMO_IN_SWIFTCOPTS,
        ) or
        are_all_features_enabled(
            feature_configuration = feature_configuration,
            feature_names = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ) or
        _is_wmo_manually_requested(user_compile_flags)
    )

    # We check the feature first because that implies that `-num-threads 0` was
    # present in `--swiftcopt`, which overrides all other flags (like the user
    # compile flags, which come from the target's `copts`). Only fallback to
    # checking the flags if the feature is disabled.
    is_single_threaded = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE__NUM_THREADS_0_IN_SWIFTCOPTS,
    ) or _find_num_threads_flag_value(user_compile_flags) == 0

    return struct(
        emits_multiple_objects = not (is_wmo and is_single_threaded),
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

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

"""BUILD rules used to provide a Swift toolchain provided by Xcode on macOS.

The rules defined in this file are not intended to be used outside of the Swift
toolchain package. If you are looking for rules to build Swift code using this
toolchain, see `swift.bzl`.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(":actions.bzl", "swift_action_names")
load(":attrs.bzl", "swift_toolchain_driver_attrs")
load(":compiling.bzl", "compile_action_configs", "features_from_swiftcopts")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_BITCODE_EMBEDDED",
    "SWIFT_FEATURE_BITCODE_EMBEDDED_MARKERS",
    "SWIFT_FEATURE_BUNDLED_XCTESTS",
    "SWIFT_FEATURE_COVERAGE",
    "SWIFT_FEATURE_COVERAGE_PREFIX_MAP",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_ENABLE_SKIP_FUNCTION_BODIES",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS",
    "SWIFT_FEATURE_REMAP_XCODE_PATH",
    "SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS",
    "SWIFT_FEATURE_SUPPORTS_SYSTEM_MODULE_FLAG",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
)
load(":features.bzl", "features_for_build_modes")
load(":toolchain_config.bzl", "swift_toolchain_config")
load(
    ":providers.bzl",
    "SwiftFeatureAllowlistInfo",
    "SwiftInfo",
    "SwiftPackageConfigurationInfo",
    "SwiftToolchainInfo",
)
load(
    ":utils.bzl",
    "collect_implicit_deps_providers",
    "compact",
    "get_swift_executable_for_toolchain",
    "resolve_optional_tool",
)

def _swift_developer_lib_dir(platform_framework_dir):
    """Returns the directory containing extra Swift developer libraries.

    Args:
        platform_framework_dir: The developer platform framework directory for
            the current platform.

    Returns:
        The directory containing extra Swift-specific development libraries and
        swiftmodules.
    """
    return paths.join(
        paths.dirname(paths.dirname(platform_framework_dir)),
        "usr",
        "lib",
    )

def _command_line_objc_copts(compilation_mode, objc_fragment):
    """Returns copts that should be passed to `clang` from the `objc` fragment.

    Args:
        compilation_mode: The current compilation mode.
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

    clang_copts = objc_fragment.copts + legacy_copts
    return [copt for copt in clang_copts if copt != "-g"]

def _platform_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config):
    """Returns the Developer framework directory for the platform.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        xcode_config: The Xcode configuration.

    Returns:
        The path to the Developer framework directory for the platform if one
        exists, otherwise `None`.
    """

    # All platforms have a `Developer/Library/Frameworks` directory in their
    # platform root, except for watchOS prior to Xcode 12.5.
    platform_type = apple_fragment.single_arch_platform.platform_type
    if (
        platform_type == apple_common.platform_type.watchos and
        not _is_xcode_at_least_version(xcode_config, "12.5")
    ):
        return None

    return apple_toolchain.platform_developer_framework_dir(apple_fragment)

def _sdk_developer_framework_dir(apple_toolchain, apple_fragment, xcode_config):
    """Returns the Developer framework directory for the SDK.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        xcode_config: The Xcode configuration.

    Returns:
        The path to the Developer framework directory for the SDK if one
        exists, otherwise `None`.
    """

    # All platforms have a `Developer/Library/Frameworks` directory in their SDK
    # root except for macOS (all versions of Xcode so far), and watchOS (prior
    # to Xcode 12.5).
    platform_type = apple_fragment.single_arch_platform.platform_type
    if (
        platform_type == apple_common.platform_type.macos or
        (
            platform_type == apple_common.platform_type.watchos and
            not _is_xcode_at_least_version(xcode_config, "12.5")
        )
    ):
        return None

    return paths.join(apple_toolchain.sdk_dir(), "Developer/Library/Frameworks")

def _swift_linkopts_providers(
        apple_fragment,
        apple_toolchain,
        platform,
        toolchain_label,
        xcode_config):
    """Returns providers containing flags that should be passed to the linker.

    The providers returned by this function will be used as implicit
    dependencies of the toolchain to ensure that any binary containing Swift code
    will link to the standard libraries correctly.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        platform: The `apple_platform` value describing the target platform.
        toolchain_label: The label of the Swift toolchain that will act as the
            owner of the linker input propagating the flags.
        xcode_config: The Xcode configuration.

    Returns:
        A `struct` containing the following fields:

        *   `cc_info`: A `CcInfo` provider that will provide linker flags to
            binaries that depend on Swift targets.
        *   `objc_info`: An `apple_common.Objc` provider that will provide
            linker flags to binaries that depend on Swift targets.
    """
    platform_developer_framework_dir = _platform_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config,
    )
    sdk_developer_framework_dir = _sdk_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config,
    )
    swift_lib_dir = paths.join(
        apple_toolchain.developer_dir(),
        "Toolchains/XcodeDefault.xctoolchain/usr/lib/swift",
        platform.name_in_plist.lower(),
    )

    linkopts = [
        "-F{}".format(path)
        for path in compact([
            platform_developer_framework_dir,
            sdk_developer_framework_dir,
        ])
    ] + [
        "-Wl,-rpath,/usr/lib/swift",
        "-L{}".format(swift_lib_dir),
        "-L/usr/lib/swift",
        # TODO(b/112000244): These should get added by the C++ Starlark API,
        # but we're using the "c++-link-executable" action right now instead
        # of "objc-executable" because the latter requires additional
        # variables not provided by cc_common. Figure out how to handle this
        # correctly.
        "-ObjC",
        "-Wl,-objc_abi_version,2",
    ]

    # Add the linker path to the directory containing the dylib with Swift
    # extensions for the XCTest module.
    if platform_developer_framework_dir:
        linkopts.extend([
            "-L{}".format(
                _swift_developer_lib_dir(platform_developer_framework_dir),
            ),
        ])

    return struct(
        cc_info = CcInfo(
            linking_context = cc_common.create_linking_context(
                linker_inputs = depset([
                    cc_common.create_linker_input(
                        owner = toolchain_label,
                        user_link_flags = depset(linkopts),
                    ),
                ]),
            ),
        ),
        objc_info = apple_common.new_objc_provider(linkopt = depset(linkopts)),
    )

def _features_for_bitcode_mode(bitcode_mode):
    """Gets the list of features to enable for the selected Bitcode mode.

    Args:
        bitcode_mode: The `bitcode_mode` value from the C++ configuration
            fragment.

    Returns:
        A list containing the features to enable.
    """
    bitcode_mode_string = str(bitcode_mode)
    if bitcode_mode_string == "embedded":
        return [SWIFT_FEATURE_BITCODE_EMBEDDED]
    elif bitcode_mode_string == "embedded_markers":
        return [SWIFT_FEATURE_BITCODE_EMBEDDED_MARKERS]
    elif bitcode_mode_string == "none":
        return []

    fail("Internal error: expected bitcode_mode to be one of: " +
         "['embedded', 'embedded_markers', 'none'], but got '{}'".format(
             bitcode_mode_string,
         ))

def _resource_directory_configurator(developer_dir, _prerequisites, args):
    """Configures compiler flags about the toolchain's resource directory.

    We must pass a resource directory explicitly if the build rules are invoked
    using a custom driver executable or a partial toolchain root, so that the
    compiler doesn't try to find its resources relative to that binary.

    Args:
        developer_dir: The path to Xcode's Developer directory. This argument is
            pre-bound in the partial.
        _prerequisites: The value returned by
            `swift_common.action_prerequisites`.
        args: The `Args` object to which flags will be added.
    """
    args.add(
        "-resource-dir",
        (
            "{developer_dir}/Toolchains/{toolchain}.xctoolchain/" +
            "usr/lib/swift"
        ).format(
            developer_dir = developer_dir,
            toolchain = "XcodeDefault",
        ),
    )

def _all_action_configs(
        additional_objc_copts,
        additional_swiftc_copts,
        apple_fragment,
        apple_toolchain,
        generated_header_rewriter,
        needs_resource_directory,
        target_triple,
        xcode_config):
    """Returns the action configurations for the Swift toolchain.

    Args:
        additional_objc_copts: Additional Objective-C compiler flags obtained
            from the `objc` configuration fragment (and legacy flags that were
            previously passed directly by Bazel).
        additional_swiftc_copts: Additional Swift compiler flags obtained from
            the `swift` configuration fragment.
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        generated_header_rewriter: An executable that will be invoked after
            compilation to rewrite the generated header, or None if this is not
            desired.
        needs_resource_directory: If True, the toolchain needs the resource
            directory passed explicitly to the compiler.
        target_triple: The target triple.
        xcode_config: The Xcode configuration.

    Returns:
        The action configurations for the Swift toolchain.
    """
    platform_developer_framework_dir = _platform_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config,
    )
    sdk_developer_framework_dir = _sdk_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config,
    )
    developer_framework_dirs = compact([
        platform_developer_framework_dir,
        sdk_developer_framework_dir,
    ])

    # Basic compilation flags (target triple and toolchain search paths).
    action_configs = [
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
                swift_action_names.PRECOMPILE_C_MODULE,
                swift_action_names.DUMP_AST,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-target", target_triple),
                swift_toolchain_config.add_arg(
                    "-sdk",
                    apple_toolchain.sdk_dir(),
                ),
            ] + [
                swift_toolchain_config.add_arg(framework_dir, format = "-F%s")
                for framework_dir in developer_framework_dirs
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.PRECOMPILE_C_MODULE],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-Xcc",
                    framework_dir,
                    format = "-F%s",
                )
                for framework_dir in developer_framework_dirs
            ],
        ),
    ]

    # The platform developer framework directory contains XCTest.swiftmodule
    # with Swift extensions to XCTest, so it needs to be added to the search
    # path on platforms where it exists.
    if platform_developer_framework_dir:
        action_configs.append(
            swift_toolchain_config.action_config(
                actions = [
                    swift_action_names.COMPILE,
                    swift_action_names.DERIVE_FILES,
                    swift_action_names.PRECOMPILE_C_MODULE,
                    swift_action_names.DUMP_AST,
                ],
                configurators = [
                    swift_toolchain_config.add_arg(
                        _swift_developer_lib_dir(
                            platform_developer_framework_dir,
                        ),
                        format = "-I%s",
                    ),
                ],
            ),
        )

    action_configs.extend([
        # Bitcode-related flags.
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [swift_toolchain_config.add_arg("-embed-bitcode")],
            features = [SWIFT_FEATURE_BITCODE_EMBEDDED],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.PRECOMPILE_C_MODULE,
            ],
            configurators = [
                swift_toolchain_config.add_arg("-embed-bitcode-marker"),
            ],
            features = [SWIFT_FEATURE_BITCODE_EMBEDDED_MARKERS],
        ),

        # Xcode path remapping
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-debug-prefix-map",
                    "__BAZEL_XCODE_DEVELOPER_DIR__=DEVELOPER_DIR",
                ),
            ],
            features = [
                [SWIFT_FEATURE_REMAP_XCODE_PATH, SWIFT_FEATURE_DEBUG_PREFIX_MAP],
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [
                swift_action_names.COMPILE,
                swift_action_names.DERIVE_FILES,
            ],
            configurators = [
                swift_toolchain_config.add_arg(
                    "-coverage-prefix-map",
                    "__BAZEL_XCODE_DEVELOPER_DIR__=DEVELOPER_DIR",
                ),
            ],
            features = [
                [
                    SWIFT_FEATURE_REMAP_XCODE_PATH,
                    SWIFT_FEATURE_COVERAGE_PREFIX_MAP,
                    SWIFT_FEATURE_COVERAGE,
                ],
            ],
        ),
    ])

    if needs_resource_directory:
        # If the user is using a custom driver but not a complete custom
        # toolchain, provide the original toolchain's resources as the resource
        # directory so that modules are found correctly.
        action_configs.append(
            swift_toolchain_config.action_config(
                actions = [
                    swift_action_names.COMPILE,
                    swift_action_names.DERIVE_FILES,
                    swift_action_names.PRECOMPILE_C_MODULE,
                    swift_action_names.DUMP_AST,
                ],
                configurators = [
                    partial.make(
                        _resource_directory_configurator,
                        apple_toolchain.developer_dir(),
                    ),
                ],
            ),
        )

    action_configs.extend(compile_action_configs(
        additional_objc_copts = additional_objc_copts,
        additional_swiftc_copts = additional_swiftc_copts,
        generated_header_rewriter = generated_header_rewriter.executable,
    ))
    return action_configs

def _all_tool_configs(
        custom_toolchain,
        env,
        execution_requirements,
        generated_header_rewriter,
        swift_executable,
        toolchain_root,
        xcode_config):
    """Returns the tool configurations for the Swift toolchain.

    Args:
        custom_toolchain: The bundle identifier of a custom Swift toolchain, if
            one was requested.
        env: The environment variables to set when launching tools.
        execution_requirements: The execution requirements for tools.
        generated_header_rewriter: A `struct` returned by
            `resolve_optional_tool` that represents an executable that will be
            invoked after compilation to rewrite the generated header.
        swift_executable: A custom Swift driver executable to be used during the
            build, if provided.
        toolchain_root: The root directory of the toolchain, if provided.
        xcode_config: The `apple_common.XcodeVersionConfig` provider.

    Returns:
        A dictionary mapping action name to tool configuration.
    """

    # Configure the environment variables that the worker needs to fill in the
    # Bazel placeholders for SDK root and developer directory, along with the
    # custom toolchain if requested.
    if custom_toolchain:
        env = dict(env)
        env["TOOLCHAINS"] = custom_toolchain

    env["SWIFT_AVOID_WARNING_USING_OLD_DRIVER"] = "1"

    tool_config = swift_toolchain_config.driver_tool_config(
        driver_mode = "swiftc",
        env = env,
        execution_requirements = execution_requirements,
        swift_executable = swift_executable,
        tool_input_manifests = generated_header_rewriter.input_manifests,
        tool_inputs = generated_header_rewriter.inputs,
        toolchain_root = toolchain_root,
        use_param_file = True,
        worker_mode = "persistent",
    )

    tool_configs = {
        swift_action_names.COMPILE: tool_config,
        swift_action_names.DERIVE_FILES: tool_config,
        swift_action_names.DUMP_AST: tool_config,
    }

    # Xcode 12.0 implies Swift 5.3.
    if _is_xcode_at_least_version(xcode_config, "12.0"):
        tool_configs[swift_action_names.PRECOMPILE_C_MODULE] = (
            swift_toolchain_config.driver_tool_config(
                driver_mode = "swiftc",
                env = env,
                execution_requirements = execution_requirements,
                swift_executable = swift_executable,
                toolchain_root = toolchain_root,
                use_param_file = True,
                worker_mode = "wrap",
            )
        )

    return tool_configs

def _is_xcode_at_least_version(xcode_config, desired_version):
    """Returns True if we are building with at least the given Xcode version.

    Args:
        xcode_config: The `apple_common.XcodeVersionConfig` provider.
        desired_version: The minimum desired Xcode version, as a dotted version
            string.

    Returns:
        True if the current target is being built with a version of Xcode at
        least as high as the given version.
    """
    current_version = xcode_config.xcode_version()
    if not current_version:
        fail("Could not determine Xcode version at all. This likely means " +
             "Xcode isn't available; if you think this is a mistake, please " +
             "file an issue.")

    desired_version_value = apple_common.dotted_version(desired_version)
    return current_version >= desired_version_value

def _swift_apple_target_triple(cpu, platform, version):
    """Returns a target triple string for an Apple platform.

    Args:
        cpu: The CPU of the target.
        platform: The `apple_platform` value describing the target platform.
        version: The target platform version as a dotted version string.

    Returns:
        A target triple string describing the platform.
    """
    platform_string = str(platform.platform_type)
    if platform_string == "macos":
        platform_string = "macosx"

    environment = ""
    if not platform.is_device:
        environment = "-simulator"

    return "{cpu}-apple-{platform}{version}{environment}".format(
        cpu = cpu,
        environment = environment,
        platform = platform_string,
        version = version,
    )

def _xcode_env(xcode_config, platform):
    """Returns a dictionary containing Xcode-related environment variables.

    Args:
        xcode_config: The `XcodeVersionConfig` provider that contains
            information about the current Xcode configuration.
        platform: The `apple_platform` value describing the target platform
            being built.

    Returns:
        A `dict` containing Xcode-related environment variables that should be
        passed to Swift compile and link actions.
    """
    return dicts.add(
        apple_common.apple_host_system_env(xcode_config),
        apple_common.target_apple_env(xcode_config, platform),
    )

def _xcode_swift_toolchain_impl(ctx):
    apple_fragment = ctx.fragments.apple
    cpp_fragment = ctx.fragments.cpp
    apple_toolchain = apple_common.apple_toolchain()
    cc_toolchain = find_cpp_toolchain(ctx)

    # TODO(https://github.com/bazelbuild/bazel/issues/14291): Always use the
    # value from ctx.fragments.apple.single_arch_cpu
    if cc_toolchain.cpu.startswith("darwin_"):
        cpu = cc_toolchain.cpu[len("darwin_"):]
    else:
        cpu = apple_fragment.single_arch_cpu

    platform = apple_fragment.single_arch_platform
    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]

    target_os_version = xcode_config.minimum_os_for_platform_type(
        platform.platform_type,
    )
    target = _swift_apple_target_triple(cpu, platform, target_os_version)

    swift_linkopts_providers = _swift_linkopts_providers(
        apple_fragment,
        apple_toolchain,
        platform,
        ctx.label,
        xcode_config,
    )

    # `--define=SWIFT_USE_TOOLCHAIN_ROOT=<path>` is a rapid development feature
    # that lets you build *just* a custom `swift` driver (and `swiftc`
    # symlink), rather than a full toolchain, and point compilation actions at
    # those. Note that the files must still be in a "toolchain-like" directory
    # structure, meaning that the path passed here must contain a `bin`
    # directory and that directory contains the `swift` and `swiftc` files.
    #
    # TODO(allevato): Retire this feature in favor of the `swift_executable`
    # attribute, which supports remote builds.
    #
    # To use a "standard" custom toolchain built using the full Swift build
    # script, use `--define=SWIFT_CUSTOM_TOOLCHAIN=<id>` as shown below.
    swift_executable = get_swift_executable_for_toolchain(ctx)
    toolchain_root = ctx.var.get("SWIFT_USE_TOOLCHAIN_ROOT")
    custom_toolchain = ctx.var.get("SWIFT_CUSTOM_TOOLCHAIN")
    if toolchain_root and custom_toolchain:
        fail("Do not use SWIFT_USE_TOOLCHAIN_ROOT and SWIFT_CUSTOM_TOOLCHAIN" +
             "in the same build.")

    # Compute the default requested features and conditional ones based on Xcode
    # version.
    requested_features = features_for_build_modes(
        ctx,
        cpp_fragment = cpp_fragment,
    ) + features_from_swiftcopts(swiftcopts = ctx.fragments.swift.copts())
    requested_features.extend(ctx.features)
    requested_features.extend(
        _features_for_bitcode_mode(cpp_fragment.apple_bitcode_mode),
    )
    requested_features.extend([
        SWIFT_FEATURE_BUNDLED_XCTESTS,
        SWIFT_FEATURE_ENABLE_BATCH_MODE,
        SWIFT_FEATURE_USE_RESPONSE_FILES,
        SWIFT_FEATURE_DEBUG_PREFIX_MAP,
        SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION,
        SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS,
        # TODO(b/142867898): Added to match existing Bazel Objective-C module
        # map behavior; remove it when possible.
        SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS,
    ])

    # Xcode 11.0 implies Swift 5.1.
    if _is_xcode_at_least_version(xcode_config, "11.0"):
        requested_features.append(SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION)
        requested_features.append(SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS)

    # Xcode 11.4 implies Swift 5.2.
    if _is_xcode_at_least_version(xcode_config, "11.4"):
        requested_features.append(SWIFT_FEATURE_ENABLE_SKIP_FUNCTION_BODIES)

    # Xcode 12.5 implies Swift 5.4.
    if _is_xcode_at_least_version(xcode_config, "12.5"):
        requested_features.append(SWIFT_FEATURE_SUPPORTS_SYSTEM_MODULE_FLAG)

    env = _xcode_env(platform = platform, xcode_config = xcode_config)
    execution_requirements = xcode_config.execution_info()
    generated_header_rewriter = resolve_optional_tool(
        ctx,
        target = ctx.attr.generated_header_rewriter,
    )

    all_tool_configs = _all_tool_configs(
        custom_toolchain = custom_toolchain,
        env = env,
        execution_requirements = execution_requirements,
        generated_header_rewriter = generated_header_rewriter,
        swift_executable = swift_executable,
        toolchain_root = toolchain_root,
        xcode_config = xcode_config,
    )
    all_action_configs = _all_action_configs(
        additional_objc_copts = _command_line_objc_copts(
            ctx.var["COMPILATION_MODE"],
            ctx.fragments.objc,
        ),
        additional_swiftc_copts = ctx.fragments.swift.copts(),
        apple_fragment = apple_fragment,
        apple_toolchain = apple_toolchain,
        generated_header_rewriter = generated_header_rewriter,
        needs_resource_directory = swift_executable or toolchain_root,
        target_triple = target,
        xcode_config = xcode_config,
    )

    return [
        SwiftToolchainInfo(
            action_configs = all_action_configs,
            cc_toolchain_info = cc_toolchain,
            clang_implicit_deps_providers = collect_implicit_deps_providers(
                ctx.attr.clang_implicit_deps,
            ),
            feature_allowlists = [
                target[SwiftFeatureAllowlistInfo]
                for target in ctx.attr.feature_allowlists
            ],
            generated_header_module_implicit_deps_providers = (
                collect_implicit_deps_providers(
                    ctx.attr.generated_header_module_implicit_deps,
                )
            ),
            implicit_deps_providers = collect_implicit_deps_providers(
                ctx.attr.implicit_deps + ctx.attr.clang_implicit_deps,
                additional_cc_infos = [swift_linkopts_providers.cc_info],
                additional_objc_infos = [swift_linkopts_providers.objc_info],
            ),
            linker_supports_filelist = True,
            package_configurations = [
                target[SwiftPackageConfigurationInfo]
                for target in ctx.attr.package_configurations
            ],
            requested_features = requested_features,
            swift_worker = ctx.executable._worker,
            test_configuration = struct(
                env = env,
                execution_requirements = execution_requirements,
            ),
            tool_configs = all_tool_configs,
            unsupported_features = ctx.disabled_features + [
                SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
            ],
        ),
    ]

xcode_swift_toolchain = rule(
    attrs = dicts.add(
        swift_toolchain_driver_attrs(),
        {
            "clang_implicit_deps": attr.label_list(
                doc = """\
A list of labels to library targets that should be unconditionally added as
implicit dependencies of any explicit C/Objective-C module compiled by the Swift
toolchain and also as implicit dependencies of any Swift modules compiled by
the Swift toolchain.

Despite being C/Objective-C modules, the targets specified by this attribute
must propagate the `SwiftInfo` provider because the Swift build rules use that
provider to look up Clang module requirements. In particular, the targets must
propagate the provider in their rule implementation themselves and not rely on
the implicit traversal performed by `swift_clang_module_aspect`; the latter is
not possible as it would create a dependency cycle between the toolchain and the
implicit dependencies.
""",
                providers = [[SwiftInfo]],
            ),
            "feature_allowlists": attr.label_list(
                doc = """\
A list of `swift_feature_allowlist` targets that allow or prohibit packages from
requesting or disabling features.
""",
                providers = [[SwiftFeatureAllowlistInfo]],
            ),
            "generated_header_module_implicit_deps": attr.label_list(
                doc = """\
Targets whose `SwiftInfo` providers should be treated as compile-time inputs to
actions that precompile the explicit module for the generated Objective-C header
of a Swift module.
""",
                providers = [[SwiftInfo]],
            ),
            "generated_header_rewriter": attr.label(
                allow_files = True,
                cfg = "exec",
                doc = """\
If present, an executable that will be invoked after compilation to rewrite the
generated header.

This tool is expected to have a command line interface such that the Swift
compiler invocation is passed to it following a `"--"` argument, and any
arguments preceding the `"--"` can be defined by the tool itself (however, at
this time the worker does not support passing additional flags to the tool).
""",
                executable = True,
            ),
            "implicit_deps": attr.label_list(
                allow_files = True,
                doc = """\
A list of labels to library targets that should be unconditionally added as
implicit dependencies of any Swift compilation or linking target.
""",
                providers = [
                    [CcInfo],
                    [SwiftInfo],
                ],
            ),
            "package_configurations": attr.label_list(
                doc = """\
A list of `swift_package_configuration` targets that specify additional compiler
configuration options that are applied to targets on a per-package basis.
""",
                providers = [[SwiftPackageConfigurationInfo]],
            ),
            "_cc_toolchain": attr.label(
                default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
                doc = """\
The C++ toolchain from which linking flags and other tools needed by the Swift
toolchain (such as `clang`) will be retrieved.
""",
            ),
            "_worker": attr.label(
                cfg = "exec",
                allow_files = True,
                default = Label(
                    "@build_bazel_rules_swift//tools/worker:worker_wrapper",
                ),
                doc = """\
An executable that wraps Swift compiler invocations and also provides support
for incremental compilation using a persistent mode.
""",
                executable = True,
            ),
            "_xcode_config": attr.label(
                default = configuration_field(
                    name = "xcode_config_label",
                    fragment = "apple",
                ),
            ),
        },
    ),
    doc = "Represents a Swift compiler toolchain provided by Xcode.",
    fragments = [
        "apple",
        "cpp",
        "objc",
        "swift",
    ],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    incompatible_use_toolchain_transition = True,
    implementation = _xcode_swift_toolchain_impl,
)

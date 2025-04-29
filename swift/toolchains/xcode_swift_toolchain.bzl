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
toolchain, see `doc/rules.md`.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain", "use_cpp_toolchain")
load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftFeatureAllowlistInfo",
    "SwiftInfo",
    "SwiftPackageConfigurationInfo",
    "SwiftToolchainInfo",
)
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
    "@build_bazel_rules_swift//swift/internal:attrs.bzl",
    "swift_toolchain_driver_attrs",
)
load(
    "@build_bazel_rules_swift//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_COMPILE_IN_PARALLEL",
    "SWIFT_FEATURE_MODULE_HOME_IS_CWD",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
)
load(
    "@build_bazel_rules_swift//swift/internal:features.bzl",
    "default_features_for_toolchain",
    "features_for_build_modes",
)
load(
    "@build_bazel_rules_swift//swift/internal:optimization.bzl",
    "optimization_features_from_swiftcopts",
)
load(
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    "SwiftCrossImportOverlayInfo",
    "SwiftModuleAliasesInfo",
)
load(
    "@build_bazel_rules_swift//swift/internal:target_triples.bzl",
    "target_triples",
)
load(
    "@build_bazel_rules_swift//swift/internal:utils.bzl",
    "collect_implicit_deps_providers",
    "compact",
    "get_swift_executable_for_toolchain",
)
load(
    "@build_bazel_rules_swift//swift/toolchains/config:action_config.bzl",
    "ActionConfigInfo",
    "add_arg",
)
load(
    "@build_bazel_rules_swift//swift/toolchains/config:all_actions_config.bzl",
    "all_actions_action_configs",
)
load(
    "@build_bazel_rules_swift//swift/toolchains/config:compile_config.bzl",
    "command_line_objc_copts",
    "compile_action_configs",
)
load(
    "@build_bazel_rules_swift//swift/toolchains/config:compile_module_interface_config.bzl",
    "compile_module_interface_action_configs",
)
load(
    "@build_bazel_rules_swift//swift/toolchains/config:default_warnings_as_errors.bzl",
    "default_warnings_as_errors_features",
)
load(
    "@build_bazel_rules_swift//swift/toolchains/config:symbol_graph_config.bzl",
    "symbol_graph_action_configs",
)
load(
    "@build_bazel_rules_swift//swift/toolchains/config:synthesize_interface_config.bzl",
    "synthesize_interface_action_configs",
)
load(
    "@build_bazel_rules_swift//swift/toolchains/config:tool_config.bzl",
    "ToolConfigInfo",
)

visibility("public")

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

def _platform_developer_framework_dir(developer_dir, target_triple):
    """Returns the Developer framework directory for the platform.

    Args:
        developer_dir: The path to Xcode's "Developer" directory.
        target_triple: The triple of the platform being targeted.

    Returns:
        The path to the Developer framework directory for the platform if one
        exists, otherwise `None`.
    """
    return paths.join(
        developer_dir,
        "Platforms",
        "{}.platform".format(
            target_triples.bazel_apple_platform(target_triple).name_in_plist,
        ),
        "Developer/Library/Frameworks",
    )

def _sdk_developer_framework_dir(apple_toolchain, target_triple):
    """Returns the Developer framework directory for the SDK.

    Args:
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        target_triple: The triple of the platform being targeted.

    Returns:
        The path to the Developer framework directory for the SDK if one
        exists, otherwise `None`.
    """

    # All platforms have a `Developer/Library/Frameworks` directory in their SDK
    # root except for macOS.
    os = target_triples.unversioned_os(target_triple)
    if os == "macos":
        return None

    return paths.join(apple_toolchain.sdk_dir(), "Developer/Library/Frameworks")

def _swift_linkopts_cc_info(
        apple_toolchain,
        target_triple,
        toolchain_label):
    """Returns a `CcInfo` containing flags that should be passed to the linker.

    The providers returned by this function will be used as implicit
    dependencies of the toolchain to ensure that any binary containing Swift
    code will link to the standard libraries correctly.

    Args:
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        target_triple: The target triple `struct`.
        toolchain_label: The label of the Swift toolchain that will act as the
            owner of the linker input propagating the flags.

    Returns:
        A `CcInfo` provider that will provide linker flags to binaries that
        depend on Swift targets.
    """
    platform_developer_framework_dir = _platform_developer_framework_dir(
        apple_toolchain.developer_dir(),
        target_triple,
    )
    sdk_developer_framework_dir = _sdk_developer_framework_dir(
        apple_toolchain,
        target_triple,
    )
    swift_lib_dir = paths.join(
        apple_toolchain.developer_dir(),
        "Toolchains/XcodeDefault.xctoolchain/usr/lib/swift",
        target_triples.platform_name_for_swift(target_triple),
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
        # TODO(b/112000244): This should get added by the C++ Starlark API,
        # but we're using the "c++-link-executable" action right now instead
        # of "objc-executable" because the latter requires additional
        # variables not provided by cc_common. Figure out how to handle this
        # correctly.
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

    return CcInfo(
        linking_context = cc_common.create_linking_context(
            linker_inputs = depset([
                cc_common.create_linker_input(
                    owner = toolchain_label,
                    user_link_flags = depset(linkopts),
                ),
            ]),
        ),
    )

def _test_linking_context(target_triple, toolchain_label):
    """Returns a `CcLinkingContext` containing linker flags for test binaries.

    Args:
        target_triple: The target triple `struct`.
        toolchain_label: The label of the Swift toolchain that will act as the
            owner of the linker input propagating the flags.

    Returns:
        A `CcLinkingContext` that will provide linker flags to `swift_test`
        binaries.
    """

    # xcode-select creates the following symlink(s) to the developer directory
    # (we list both because the behavior changed between versions of macOS).
    # We use these as the rpaths for linking tests so that the required
    # libraries are found if Xcode is installed in a different location on the
    # machine that runs the tests than the machine used to link them.
    developer_dirs = [
        "/private/var/select/developer_dir",
        "/var/db/xcode_select_link",
    ]
    linkopts = []
    for developer_dir in developer_dirs:
        platform_developer_framework_dir = _platform_developer_framework_dir(
            developer_dir,
            target_triple,
        )
        linkopts.extend([
            "-Wl,-rpath,{}".format(path)
            for path in compact([
                _swift_developer_lib_dir(platform_developer_framework_dir),
                platform_developer_framework_dir,
            ])
        ])

    return cc_common.create_linking_context(
        linker_inputs = depset([
            cc_common.create_linker_input(
                owner = toolchain_label,
                user_link_flags = depset(linkopts),
            ),
        ]),
    )

def _make_resource_directory_configurator(developer_dir):
    """Makes a configurator for resource-directory-related compiler flags.

    We must pass a resource directory explicitly if the build rules are invoked
    using a custom driver executable or a partial toolchain root, so that the
    compiler doesn't try to find its resources relative to that binary.

    Args:
        developer_dir: The path to Xcode's Developer directory.

    Returns:
        A function that is used to configure the toolchain's resource directory.
    """

    def _resource_directory_configurator(_prerequisites, args):
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

    return _resource_directory_configurator

def _all_action_configs(
        additional_objc_copts,
        additional_swiftc_copts,
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
            the `.../swift:copt` build setting.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        generated_header_rewriter: An executable that will be invoked after
            compilation to rewrite the generated header, or None if this is not
            desired.
        needs_resource_directory: If True, the toolchain needs the resource
            directory passed explicitly to the compiler.
        target_triple: The triple of the platform being targeted.
        xcode_config: The Xcode configuration.

    Returns:
        The action configurations for the Swift toolchain.
    """
    platform_developer_framework_dir = _platform_developer_framework_dir(
        apple_toolchain.developer_dir(),
        target_triple,
    )
    sdk_developer_framework_dir = _sdk_developer_framework_dir(
        apple_toolchain,
        target_triple,
    )
    developer_framework_dirs = compact([
        platform_developer_framework_dir,
        sdk_developer_framework_dir,
    ])

    # Basic compilation flags (target triple and toolchain search paths).
    action_configs = [
        ActionConfigInfo(
            actions = all_compile_action_names() + [
                SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [
                add_arg("-target", target_triples.str(target_triple)),
                add_arg("-sdk", apple_toolchain.sdk_dir()),
            ] + [
                add_arg(framework_dir, format = "-F%s")
                for framework_dir in developer_framework_dirs
            ],
        ),
        ActionConfigInfo(
            actions = [
                SWIFT_ACTION_PRECOMPILE_C_MODULE,
                SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                SWIFT_ACTION_SYNTHESIZE_INTERFACE,
            ],
            configurators = [
                add_arg("-Xcc", framework_dir, format = "-F%s")
                for framework_dir in developer_framework_dirs
            ],
        ),
    ]

    # The platform developer framework directory contains XCTest.swiftmodule
    # with Swift extensions to XCTest, so it needs to be added to the search
    # path on platforms where it exists.
    if platform_developer_framework_dir:
        action_configs.append(
            ActionConfigInfo(
                actions = all_compile_action_names() + [
                    SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
                    SWIFT_ACTION_PRECOMPILE_C_MODULE,
                    SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                    SWIFT_ACTION_SYNTHESIZE_INTERFACE,
                ],
                configurators = [
                    add_arg(
                        _swift_developer_lib_dir(
                            platform_developer_framework_dir,
                        ),
                        format = "-I%s",
                    ),
                ],
            ),
        )

    if needs_resource_directory:
        # If the user is using a custom driver but not a complete custom
        # toolchain, provide the original toolchain's resources as the resource
        # directory so that modules are found correctly.
        action_configs.append(
            ActionConfigInfo(
                actions = all_compile_action_names() + [
                    SWIFT_ACTION_PRECOMPILE_C_MODULE,
                    SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
                    SWIFT_ACTION_SYNTHESIZE_INTERFACE,
                ],
                configurators = [
                    _make_resource_directory_configurator(
                        apple_toolchain.developer_dir(),
                    ),
                ],
            ),
        )

    # For `.swiftinterface` compilation actions, always pass the resource
    # directory along with the target SDK version. These two flags together let
    # the frontend infer the path to the prebuilt `.swiftmodule`s inside the
    # toolchain. (This is necessary because we are invoking the frontend
    # directly, so the driver doesn't do this for us as it normally would.)
    action_configs.append(
        ActionConfigInfo(
            actions = [SWIFT_ACTION_COMPILE_MODULE_INTERFACE],
            configurators = [
                _make_resource_directory_configurator(
                    apple_toolchain.developer_dir(),
                ),
                add_arg(
                    "-target-sdk-version",
                    str(xcode_config.sdk_version_for_platform(
                        target_triples.bazel_apple_platform(target_triple),
                    )),
                ),
            ],
        ),
    )

    action_configs.extend(all_actions_action_configs())
    action_configs.extend(compile_action_configs(
        additional_objc_copts = additional_objc_copts,
        additional_swiftc_copts = additional_swiftc_copts,
        generated_header_rewriter = (
            generated_header_rewriter.executable if generated_header_rewriter else None
        ),
    ))
    action_configs.extend(symbol_graph_action_configs())
    action_configs.extend(synthesize_interface_action_configs())
    action_configs.extend(compile_module_interface_action_configs())

    return action_configs

def _swift_compile_resource_set(_os, inputs_size):
    # The `os` argument is unused, but the Starlark API requires both
    # positional arguments.
    return {"cpu": 1, "memory": 200. + inputs_size * 0.015}

def _all_tool_configs(
        custom_toolchain,
        env,
        execution_requirements,
        swift_executable,
        toolchain_root,
        xcode_config):
    """Returns the tool configurations for the Swift toolchain.

    Args:
        custom_toolchain: The bundle identifier of a custom Swift toolchain, if
            one was requested.
        env: The environment variables to set when launching tools.
        execution_requirements: The execution requirements for tools.
        swift_executable: A custom Swift driver executable to be used during the
            build, if provided.
        toolchain_root: The root directory of the toolchain, if provided.

    Returns:
        A dictionary mapping action name to tool configuration.
    """
    env = dict(env)

    # Configure the environment variables that the worker needs to fill in the
    # Bazel placeholders for SDK root and developer directory, along with the
    # custom toolchain if requested.
    if custom_toolchain:
        env["TOOLCHAINS"] = custom_toolchain

    def _driver_config(*, mode):
        return {
            "mode": mode,
            "swift_executable": swift_executable,
            "toolchain_root": toolchain_root,
        }

    standard_compile_tool_config = ToolConfigInfo(
        driver_config = _driver_config(mode = "swiftc"),
        env = env,
        execution_requirements = execution_requirements,
        resource_set = _swift_compile_resource_set,
        use_param_file = True,
        wrapped_by_worker = True,
    )
    action_configs = {
        SWIFT_ACTION_COMPILE: standard_compile_tool_config,
        SWIFT_ACTION_COMPILE_CODEGEN: standard_compile_tool_config,
        SWIFT_ACTION_COMPILE_MODULE: standard_compile_tool_config,
        SWIFT_ACTION_COMPILE_MODULE_INTERFACE: ToolConfigInfo(
            driver_config = _driver_config(mode = "swiftc"),
            args = ["-frontend"],
            env = env,
            execution_requirements = execution_requirements,
            resource_set = _swift_compile_resource_set,
            use_param_file = True,
            wrapped_by_worker = True,
        ),
        SWIFT_ACTION_PRECOMPILE_C_MODULE: ToolConfigInfo(
            driver_config = _driver_config(mode = "swiftc"),
            env = env,
            execution_requirements = execution_requirements,
            use_param_file = True,
            wrapped_by_worker = True,
        ),
        SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT: ToolConfigInfo(
            driver_config = _driver_config(mode = "swift-symbolgraph-extract"),
            env = env,
            execution_requirements = execution_requirements,
            use_param_file = True,
            wrapped_by_worker = True,
        ),
    }

    # swift-synthesize-interface is only available in Xcode 16.3 and later.
    if _is_xcode_at_least_version(xcode_config, "16.3"):
        action_configs[SWIFT_ACTION_SYNTHESIZE_INTERFACE] = ToolConfigInfo(
            driver_config = _driver_config(mode = "swift-synthesize-interface"),
            env = env,
            execution_requirements = execution_requirements,
            use_param_file = True,
            wrapped_by_worker = True,
        )

    return action_configs

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

def _xcode_env(target_triple, xcode_config):
    """Returns a dictionary containing Xcode-related environment variables.

    Args:
        target_triple: The triple of the platform being targeted.
        xcode_config: The `XcodeVersionConfig` provider that contains
            information about the current Xcode configuration.

    Returns:
        A `dict` containing Xcode-related environment variables that should be
        passed to Swift compile and link actions.
    """
    return dicts.add(
        apple_common.apple_host_system_env(xcode_config),
        apple_common.target_apple_env(
            xcode_config,
            target_triples.bazel_apple_platform(target_triple),
        ),
    )

def _dsym_provider(*, ctx):
    """Apple-specific linking extension to generate .dSYM binaries.

    This extension generates a minimal dSYM bundle that LLDB can find next to
    the built binary.
    """
    dsym_file = ctx.actions.declare_file(
        "{name}.dSYM/Contents/Resources/DWARF/{name}".format(
            name = ctx.label.name,
        ),
    )
    variables_extension = {
        "dsym_path": dsym_file.path,
    }
    return struct(
        additional_outputs = [dsym_file],
        variables_extension = variables_extension,
    )

def _entry_point_linkopts_provider(*, entry_point_name):
    """Returns linkopts to customize the entry point of a binary."""
    return struct(
        linkopts = ["-Wl,-alias,_{},_main".format(entry_point_name)],
    )

def _xcode_swift_toolchain_impl(ctx):
    cpp_fragment = ctx.fragments.cpp
    apple_toolchain = apple_common.apple_toolchain()
    cc_toolchain = find_cpp_toolchain(ctx)

    target_triple = target_triples.normalize_for_swift(
        target_triples.parse(cc_toolchain.target_gnu_system_name),
    )

    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]

    swiftcopts = ctx.attr._copts[BuildSettingInfo].value
    swift_linkopts_cc_info = _swift_linkopts_cc_info(
        apple_toolchain = apple_toolchain,
        target_triple = target_triple,
        toolchain_label = ctx.label,
    )
    test_linking_context = _test_linking_context(
        target_triple = target_triple,
        toolchain_label = ctx.label,
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
    requested_features, unsupported_features = (
        optimization_features_from_swiftcopts(swiftcopts = swiftcopts)
    )
    build_mode_requested_features, build_mode_unsupported_features = (
        features_for_build_modes(
            ctx,
            cpp_fragment = cpp_fragment,
        )
    )
    requested_features.extend(build_mode_requested_features)
    requested_features.extend(ctx.attr.default_enabled_features)
    requested_features.extend(default_features_for_toolchain(
        ctx = ctx,
        target_triple = target_triple,
    ))
    requested_features.extend(default_warnings_as_errors_features())
    requested_features.extend([
        SWIFT_FEATURE_COMPILE_IN_PARALLEL,

        # Allow users to start using access levels on `import`s by default. Note
        # that this does *not* change the default access level for `import`s to
        # `internal`; that is controlled by the upcoming feature flag
        # `InternalImportsByDefault`.
        "swift.experimental.AccessLevelOnImport",

        # Ensure hermetic PCM files (no absolute workspace paths).
        SWIFT_FEATURE_MODULE_HOME_IS_CWD,
    ])

    unsupported_features.extend(build_mode_unsupported_features)
    unsupported_features.extend(ctx.attr.default_unsupported_features)

    # `-fmodule-map-file-home-is-cwd` is incompatible with Apple's module maps,
    # which we must use for system frameworks.
    unsupported_features.append(SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD)

    env = _xcode_env(target_triple = target_triple, xcode_config = xcode_config)
    execution_requirements = xcode_config.execution_info()

    generated_header_rewriter = ctx.attr.generated_header_rewriter
    if generated_header_rewriter:
        generated_header_rewriter = generated_header_rewriter.files_to_run

    all_tool_configs = _all_tool_configs(
        custom_toolchain = custom_toolchain,
        env = env,
        execution_requirements = execution_requirements,
        swift_executable = swift_executable,
        toolchain_root = toolchain_root,
        xcode_config = xcode_config,
    )
    all_action_configs = _all_action_configs(
        additional_objc_copts = command_line_objc_copts(
            ctx.var["COMPILATION_MODE"],
            ctx.fragments.cpp,
            ctx.fragments.objc,
        ),
        additional_swiftc_copts = swiftcopts,
        apple_toolchain = apple_toolchain,
        generated_header_rewriter = generated_header_rewriter,
        needs_resource_directory = swift_executable or toolchain_root,
        target_triple = target_triple,
        xcode_config = xcode_config,
    )

    swift_toolchain_info = SwiftToolchainInfo(
        action_configs = all_action_configs,
        cc_language = "objc",
        cc_toolchain_info = cc_toolchain,
        clang_implicit_deps_providers = collect_implicit_deps_providers(
            ctx.attr.clang_implicit_deps,
        ),
        codegen_batch_size = 8,
        cross_import_overlays = [
            target[SwiftCrossImportOverlayInfo]
            for target in ctx.attr.cross_import_overlays
        ],
        debug_outputs_provider = (
            # This function unconditionally declares the output file, so we
            # should only use it if a .dSYM is being requested during the build.
            _dsym_provider if cpp_fragment.apple_generate_dsym else None
        ),
        entry_point_linkopts_provider = _entry_point_linkopts_provider,
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
            additional_cc_infos = [swift_linkopts_cc_info],
        ),
        module_aliases = (
            ctx.attr._module_mapping[SwiftModuleAliasesInfo].aliases
        ),
        package_configurations = [
            target[SwiftPackageConfigurationInfo]
            for target in ctx.attr.package_configurations
        ],
        requested_features = requested_features,
        swift_worker = ctx.executable._worker,
        test_configuration = struct(
            binary_name = "{name}.xctest/Contents/MacOS/{name}",
            env = env,
            execution_requirements = execution_requirements,
            objc_test_discovery = True,
            test_linking_contexts = [test_linking_context],
        ),
        tool_configs = all_tool_configs,
        unsupported_features = unsupported_features,
    )

    return [
        platform_common.ToolchainInfo(
            swift_toolchain = swift_toolchain_info,
        ),
        # TODO(b/205018581): Remove this legacy propagation when everything is
        # migrated over to new-style toolchains.
        swift_toolchain_info,
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
            "cross_import_overlays": attr.label_list(
                allow_empty = True,
                doc = """\
A list of `swift_cross_import_overlay` targets that will be automatically
injected into the dependencies of Swift compilations if their declaring module
and bystanding module are both already declared as dependencies.
""",
                mandatory = False,
                providers = [[SwiftCrossImportOverlayInfo]],
            ),
            "default_enabled_features": attr.string_list(
                doc = """\
A list of features that are enabled by default for all targets build with this
toolchain.
""",
            ),
            "default_unsupported_features": attr.string_list(
                doc = """\
A list of features that are unsupported by this toolchain.
""",
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
arguments preceding the `"--"` can be defined by the tool itself.
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
            "_copts": attr.label(
                default = Label("@build_bazel_rules_swift//swift:copt"),
                doc = """\
The label of the `string_list` containing additional flags that should be passed
to the compiler.
""",
            ),
            "_module_mapping": attr.label(
                default = Label(
                    "@build_bazel_rules_swift//swift:module_mapping",
                ),
                providers = [[SwiftModuleAliasesInfo]],
            ),
            "_worker": attr.label(
                cfg = "exec",
                allow_files = True,
                default = Label(
                    "@build_bazel_rules_swift//tools/worker",
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
        "cpp",
        "objc",
    ],
    toolchains = use_cpp_toolchain(),
    implementation = _xcode_swift_toolchain_impl,
)

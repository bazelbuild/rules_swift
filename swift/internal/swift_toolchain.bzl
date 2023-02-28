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

"""BUILD rules used to provide a Swift toolchain on Linux.

The rules defined in this file are not intended to be used outside of the Swift
toolchain package. If you are looking for rules to build Swift code using this
toolchain, see `swift.bzl`.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(":actions.bzl", "swift_action_names")
load(":attrs.bzl", "swift_toolchain_driver_attrs")
load(":autolinking.bzl", "autolink_extract_action_configs")
load(":compiling.bzl", "compile_action_configs", "features_from_swiftcopts")
load(":debugging.bzl", "modulewrap_action_configs")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_CACHEABLE_SWIFTMODULES",
    "SWIFT_FEATURE_COVERAGE_PREFIX_MAP",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_USE_AUTOLINK_EXTRACT",
    "SWIFT_FEATURE_USE_GLOBAL_INDEX_STORE",
    "SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE",
    "SWIFT_FEATURE_USE_MODULE_WRAP",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
)
load(":features.bzl", "features_for_build_modes")
load(
    ":providers.bzl",
    "SwiftFeatureAllowlistInfo",
    "SwiftPackageConfigurationInfo",
    "SwiftToolchainInfo",
)
load(":toolchain_config.bzl", "swift_toolchain_config")
load(
    ":utils.bzl",
    "collect_implicit_deps_providers",
    "get_swift_executable_for_toolchain",
)

def _all_tool_configs(
        env,
        swift_executable,
        toolchain_root,
        use_param_file,
        use_autolink_extract,
        use_module_wrap,
        additional_tools,
        tool_executable_suffix):
    """Returns the tool configurations for the Swift toolchain.

    Args:
        env: A custom environment to execute the tools in.
        swift_executable: A custom Swift driver executable to be used during the
            build, if provided.
        toolchain_root: The root directory of the toolchain.
        use_param_file: If True, the compile action should use a param file for
            its arguments.
        use_autolink_extract: If True, the link action should use
            `swift-autolink-extract` to extract the complier directed linking
            flags.
        use_module_wrap: If True, the compile action should embed the
            swiftmodule into the final image.
        additional_tools: Any extra tool inputs to pass to each driver config
        tool_executable_suffix: The suffix for executable tools to use (e.g.
            `.exe` on Windows).

    Returns:
        A dictionary mapping action name to tool configurations.
    """
    _swift_driver_tool_config = swift_toolchain_config.driver_tool_config

    tool_inputs = depset(additional_tools)

    compile_tool_config = _swift_driver_tool_config(
        driver_mode = "swiftc",
        swift_executable = swift_executable,
        tool_inputs = tool_inputs,
        toolchain_root = toolchain_root,
        tool_executable_suffix = tool_executable_suffix,
        use_param_file = use_param_file,
        worker_mode = "persistent",
        env = env,
    )

    configs = {
        swift_action_names.COMPILE: compile_tool_config,
        swift_action_names.DERIVE_FILES: compile_tool_config,
        swift_action_names.DUMP_AST: compile_tool_config,
    }

    if use_autolink_extract:
        configs[swift_action_names.AUTOLINK_EXTRACT] = _swift_driver_tool_config(
            driver_mode = "swift-autolink-extract",
            swift_executable = swift_executable,
            tool_inputs = tool_inputs,
            toolchain_root = toolchain_root,
            tool_executable_suffix = tool_executable_suffix,
            worker_mode = "wrap",
        )

    if use_module_wrap:
        configs[swift_action_names.MODULEWRAP] = _swift_driver_tool_config(
            # This must come first after the driver name.
            args = ["-modulewrap"],
            driver_mode = "swift",
            swift_executable = swift_executable,
            tool_inputs = tool_inputs,
            toolchain_root = toolchain_root,
            tool_executable_suffix = tool_executable_suffix,
            worker_mode = "wrap",
        )
    return configs

def _all_action_configs(os, arch, sdkroot, xctest_version, additional_swiftc_copts):
    """Returns the action configurations for the Swift toolchain.

    Args:
        os: The OS that we are compiling for.
        arch: The architecture we are compiling for.
        sdkroot: The path to the SDK that we should use to build against.
        xctest_version: The version of XCTest to use.
        additional_swiftc_copts: Additional Swift compiler flags obtained from
            the `swift` configuration fragment.

    Returns:
        A list of action configurations for the toolchain.
    """
    return (
        compile_action_configs(
            os = os,
            arch = arch,
            sdkroot = sdkroot,
            xctest_version = xctest_version,
            additional_swiftc_copts = additional_swiftc_copts,
        ) +
        modulewrap_action_configs() +
        autolink_extract_action_configs()
    )

def _swift_windows_linkopts_cc_info(
        arch,
        sdkroot,
        xctest_version,
        toolchain_label):
    """Returns a `CcInfo` containing flags that should be passed to the linker.

    The provider returned by this function will be used as an implicit
    dependency of the toolchain to ensure that any binary containing Swift code
    will link to the standard libraries correctly.

    Args:
        arch: The CPU architecture, which is used as part of the library path.
        sdkroot: The path to the root of the SDK that we are building against.
        xctest_version: The version of XCTest that we are building against.
        toolchain_label: The label of the Swift toolchain that will act as the
            owner of the linker input propagating the flags.

    Returns:
        A `CcInfo` provider that will provide linker flags to binaries that
        depend on Swift targets.
    """
    platform_lib_dir = "{sdkroot}/usr/lib/swift/windows/{arch}".format(
        sdkroot = sdkroot,
        arch = arch,
    )

    runtime_object_path = "{sdkroot}/usr/lib/swift/windows/{arch}/swiftrt.obj".format(
        sdkroot = sdkroot,
        arch = arch,
    )

    linkopts = [
        "-LIBPATH:{}".format(platform_lib_dir),
        "-LIBPATH:{}".format(paths.join(sdkroot, "..", "..", "Library", "XCTest-{}".format(xctest_version), "usr", "lib", "swift", "windows", arch)),
        runtime_object_path,
    ]

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

def _swift_unix_linkopts_cc_info(
        cpu,
        os,
        toolchain_label,
        toolchain_root):
    """Returns a `CcInfo` containing flags that should be passed to the linker.

    The provider returned by this function will be used as an implicit
    dependency of the toolchain to ensure that any binary containing Swift code
    will link to the standard libraries correctly.

    Args:
        cpu: The CPU architecture, which is used as part of the library path.
        os: The operating system name, which is used as part of the library
            path.
        toolchain_label: The label of the Swift toolchain that will act as the
            owner of the linker input propagating the flags.
        toolchain_root: The toolchain's root directory.

    Returns:
        A `CcInfo` provider that will provide linker flags to binaries that
        depend on Swift targets.
    """

    # TODO(#8): Support statically linking the Swift runtime.
    platform_lib_dir = "{toolchain_root}/lib/swift/{os}".format(
        os = os,
        toolchain_root = toolchain_root,
    )

    runtime_object_path = "{platform_lib_dir}/{cpu}/swiftrt.o".format(
        cpu = cpu,
        platform_lib_dir = platform_lib_dir,
    )

    linkopts = [
        "-pie",
        "-L{}".format(platform_lib_dir),
        "-Wl,-rpath,{}".format(platform_lib_dir),
        "-lm",
        "-lstdc++",
        "-lrt",
        "-ldl",
        runtime_object_path,
        "-static-libgcc",
    ]

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

def _swift_toolchain_impl(ctx):
    toolchain_root = ctx.attr.root
    cc_toolchain = find_cpp_toolchain(ctx)

    if ctx.attr.os == "windows":
        swift_linkopts_cc_info = _swift_windows_linkopts_cc_info(
            ctx.attr.arch,
            ctx.attr.sdkroot,
            ctx.attr.xctest_version,
            ctx.label,
        )
    else:
        swift_linkopts_cc_info = _swift_unix_linkopts_cc_info(
            ctx.attr.arch,
            ctx.attr.os,
            ctx.label,
            toolchain_root,
        )

    # Combine build mode features, autoconfigured features, and required
    # features.
    requested_features = (
        features_for_build_modes(ctx) +
        features_from_swiftcopts(swiftcopts = ctx.fragments.swift.copts())
    )
    requested_features.extend([
        SWIFT_FEATURE_CACHEABLE_SWIFTMODULES,
        SWIFT_FEATURE_COVERAGE_PREFIX_MAP,
        SWIFT_FEATURE_DEBUG_PREFIX_MAP,
        SWIFT_FEATURE_NO_GENERATED_MODULE_MAP,
        SWIFT_FEATURE_OPT_USES_WMO,
        SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE,
        SWIFT_FEATURE_USE_RESPONSE_FILES,
    ])

    requested_features.extend(ctx.features)

    # Swift.org toolchains assume everything is just available on the PATH so we
    # we don't pass any files unless we have a custom driver executable in the
    # workspace.
    swift_executable = get_swift_executable_for_toolchain(ctx)

    all_tool_configs = _all_tool_configs(
        env = ctx.attr.env,
        swift_executable = swift_executable,
        toolchain_root = toolchain_root,
        use_param_file = SWIFT_FEATURE_USE_RESPONSE_FILES in ctx.features,
        use_autolink_extract = SWIFT_FEATURE_USE_AUTOLINK_EXTRACT in ctx.features,
        use_module_wrap = SWIFT_FEATURE_USE_MODULE_WRAP in ctx.features,
        additional_tools = [ctx.file.version_file],
        tool_executable_suffix = ctx.attr.tool_executable_suffix,
    )
    all_action_configs = _all_action_configs(
        os = ctx.attr.os,
        arch = ctx.attr.arch,
        sdkroot = ctx.attr.sdkroot,
        xctest_version = ctx.attr.xctest_version,
        additional_swiftc_copts = ctx.fragments.swift.copts(),
    )

    if ctx.attr.os == "windows":
        if ctx.attr.arch == "x86_64":
            bindir = "bin64"
        elif ctx.attr.arch == "i686":
            bindir = "bin32"
        elif ctx.attr.arch == "arm64":
            bindir = "bin64a"
        else:
            fail("unsupported arch `{}`".format(ctx.attr.arch))

        xctest = paths.normalize(paths.join(ctx.attr.sdkroot, "..", "..", "Library", "XCTest-{}".format(ctx.attr.xctest_version), "usr", bindir))
        env = dicts.add(
            ctx.attr.env,
            {"Path": xctest + ";" + ctx.attr.env["Path"]},
        )
    else:
        env = ctx.attr.env

    # TODO(allevato): Move some of the remaining hardcoded values, like object
    # format and Obj-C interop support, to attributes so that we can remove the
    # assumptions that are only valid on Linux.
    return [
        SwiftToolchainInfo(
            action_configs = all_action_configs,
            cc_toolchain_info = cc_toolchain,
            clang_implicit_deps_providers = (
                collect_implicit_deps_providers([])
            ),
            developer_dirs = [],
            feature_allowlists = [
                target[SwiftFeatureAllowlistInfo]
                for target in ctx.attr.feature_allowlists
            ],
            generated_header_module_implicit_deps_providers = (
                collect_implicit_deps_providers([])
            ),
            implicit_deps_providers = collect_implicit_deps_providers(
                [],
                additional_cc_infos = [swift_linkopts_cc_info],
            ),
            package_configurations = [
                target[SwiftPackageConfigurationInfo]
                for target in ctx.attr.package_configurations
            ],
            requested_features = requested_features,
            root_dir = toolchain_root,
            swift_worker = ctx.attr._worker[DefaultInfo].files_to_run,
            test_configuration = struct(
                env = env,
                execution_requirements = {},
            ),
            tool_configs = all_tool_configs,
            unsupported_features = ctx.disabled_features + [
                SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
                SWIFT_FEATURE_USE_GLOBAL_INDEX_STORE,
            ],
        ),
    ]

swift_toolchain = rule(
    attrs = dicts.add(
        swift_toolchain_driver_attrs(),
        {
            "arch": attr.string(
                doc = """\
The name of the architecture that this toolchain targets.

This name should match the name used in the toolchain's directory layout for
architecture-specific content, such as "x86_64" in "lib/swift/linux/x86_64".
""",
                mandatory = True,
            ),
            "feature_allowlists": attr.label_list(
                doc = """\
A list of `swift_feature_allowlist` targets that allow or prohibit packages from
requesting or disabling features.
""",
                providers = [[SwiftFeatureAllowlistInfo]],
            ),
            "os": attr.string(
                doc = """\
The name of the operating system that this toolchain targets.

This name should match the name used in the toolchain's directory layout for
platform-specific content, such as "linux" in "lib/swift/linux".
""",
                mandatory = True,
            ),
            "package_configurations": attr.label_list(
                doc = """\
A list of `swift_package_configuration` targets that specify additional compiler
configuration options that are applied to targets on a per-package basis.
""",
                providers = [[SwiftPackageConfigurationInfo]],
            ),
            "root": attr.string(
                mandatory = True,
            ),
            "version_file": attr.label(
                mandatory = True,
                allow_single_file = True,
            ),
            "_cc_toolchain": attr.label(
                default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
                doc = """\
The C++ toolchain from which other tools needed by the Swift toolchain (such as
`clang` and `ar`) will be retrieved.
""",
            ),
            "_worker": attr.label(
                cfg = "exec",
                allow_files = True,
                default = Label("//tools/worker"),
                doc = """\
An executable that wraps Swift compiler invocations and also provides support
for incremental compilation using a persistent mode.
""",
                executable = True,
            ),
            "env": attr.string_dict(
                doc = """\
The preserved environment variables required for the toolchain to operate
normally.
""",
                mandatory = False,
            ),
            "sdkroot": attr.string(
                doc = """\
The root of a SDK to be used for building the target.
""",
                mandatory = False,
            ),
            "tool_executable_suffix": attr.string(
                doc = """\
The suffix to apply to the tools when invoking them.  This is a platform
dependent value (e.g. `.exe` on Window).
""",
                mandatory = False,
            ),
            "xctest_version": attr.string(
                doc = """\
The version of XCTest that the toolchain packages.
""",
                mandatory = False,
            ),
        },
    ),
    doc = "Represents a Swift compiler toolchain.",
    fragments = ["swift"],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    incompatible_use_toolchain_transition = True,
    implementation = _swift_toolchain_impl,
)

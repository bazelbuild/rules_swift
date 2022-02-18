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
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(":actions.bzl", "swift_action_names")
load(":attrs.bzl", "swift_toolchain_driver_attrs")
load(":autolinking.bzl", "autolink_extract_action_configs")
load(":compiling.bzl", "compile_action_configs", "features_from_swiftcopts")
load(":debugging.bzl", "modulewrap_action_configs")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
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
        swift_executable,
        toolchain_root,
        use_param_file,
        additional_tools):
    """Returns the tool configurations for the Swift toolchain.

    Args:
        swift_executable: A custom Swift driver executable to be used during the
            build, if provided.
        toolchain_root: The root directory of the toolchain.
        use_param_file: If True, the compile action should use a param file for
            its arguments.
        additional_tools: Any extra tool inputs to pass to each driver config

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
        use_param_file = use_param_file,
        worker_mode = "persistent",
    )

    return {
        swift_action_names.AUTOLINK_EXTRACT: _swift_driver_tool_config(
            driver_mode = "swift-autolink-extract",
            swift_executable = swift_executable,
            tool_inputs = tool_inputs,
            toolchain_root = toolchain_root,
            worker_mode = "wrap",
        ),
        swift_action_names.COMPILE: compile_tool_config,
        swift_action_names.DERIVE_FILES: compile_tool_config,
        swift_action_names.MODULEWRAP: _swift_driver_tool_config(
            # This must come first after the driver name.
            args = ["-modulewrap"],
            driver_mode = "swift",
            swift_executable = swift_executable,
            tool_inputs = tool_inputs,
            toolchain_root = toolchain_root,
            worker_mode = "wrap",
        ),
        swift_action_names.DUMP_AST: compile_tool_config,
    }

def _all_action_configs(additional_swiftc_copts):
    """Returns the action configurations for the Swift toolchain.

    Args:
        additional_swiftc_copts: Additional Swift compiler flags obtained from
            the `swift` configuration fragment.

    Returns:
        A list of action configurations for the toolchain.
    """
    return (
        compile_action_configs(
            additional_swiftc_copts = additional_swiftc_copts,
        ) +
        modulewrap_action_configs() +
        autolink_extract_action_configs()
    )

def _swift_linkopts_cc_info(
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

    swift_linkopts_cc_info = _swift_linkopts_cc_info(
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
    requested_features.append(SWIFT_FEATURE_NO_GENERATED_MODULE_MAP)
    requested_features.extend(ctx.features)

    # Swift.org toolchains assume everything is just available on the PATH so we
    # we don't pass any files unless we have a custom driver executable in the
    # workspace.
    swift_executable = get_swift_executable_for_toolchain(ctx)

    all_tool_configs = _all_tool_configs(
        swift_executable = swift_executable,
        toolchain_root = toolchain_root,
        use_param_file = SWIFT_FEATURE_USE_RESPONSE_FILES in ctx.features,
        additional_tools = [ctx.file.version_file],
    )
    all_action_configs = _all_action_configs(
        additional_swiftc_copts = ctx.fragments.swift.copts(),
    )

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
            linker_supports_filelist = False,
            package_configurations = [
                target[SwiftPackageConfigurationInfo]
                for target in ctx.attr.package_configurations
            ],
            requested_features = requested_features,
            root_dir = toolchain_root,
            swift_worker = ctx.executable._worker,
            test_configuration = struct(
                env = {},
                execution_requirements = {},
            ),
            tool_configs = all_tool_configs,
            unsupported_features = ctx.disabled_features + [
                SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
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
        },
    ),
    doc = "Represents a Swift compiler toolchain.",
    fragments = ["swift"],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    incompatible_use_toolchain_transition = True,
    implementation = _swift_toolchain_impl,
)

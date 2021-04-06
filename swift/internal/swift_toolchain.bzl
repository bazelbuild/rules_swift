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
load("@bazel_skylib//lib:partial.bzl", "partial")
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
load(":providers.bzl", "SwiftToolchainInfo")
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

    compile_tool_config = _swift_driver_tool_config(
        driver_mode = "swiftc",
        swift_executable = swift_executable,
        toolchain_root = toolchain_root,
        use_param_file = use_param_file,
        worker_mode = "persistent",
        additional_tools = additional_tools,
    )

    return {
        swift_action_names.AUTOLINK_EXTRACT: _swift_driver_tool_config(
            driver_mode = "swift-autolink-extract",
            swift_executable = swift_executable,
            toolchain_root = toolchain_root,
            worker_mode = "wrap",
            additional_tools = additional_tools,
        ),
        swift_action_names.COMPILE: compile_tool_config,
        swift_action_names.DERIVE_FILES: compile_tool_config,
        swift_action_names.MODULEWRAP: _swift_driver_tool_config(
            # This must come first after the driver name.
            args = ["-modulewrap"],
            driver_mode = "swift",
            swift_executable = swift_executable,
            toolchain_root = toolchain_root,
            worker_mode = "wrap",
            additional_tools = additional_tools,
        ),
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

def _default_linker_opts(
        cc_toolchain,
        cpu,
        os,
        toolchain_root,
        is_static,
        is_test):
    """Returns options that should be passed by default to `clang` when linking.

    This function is wrapped in a `partial` that will be propagated as part of
    the toolchain provider. The first three arguments are pre-bound; the
    `is_static` and `is_test` arguments are expected to be passed by the caller.

    Args:
        cc_toolchain: The cpp toolchain from which the `ld` executable is
            determined.
        cpu: The CPU architecture, which is used as part of the library path.
        os: The operating system name, which is used as part of the library
            path.
        toolchain_root: The toolchain's root directory.
        is_static: `True` to link against the static version of the Swift
            runtime, or `False` to link against dynamic/shared libraries.
        is_test: `True` if the target being linked is a test target.

    Returns:
        The command line options to pass to `clang` to link against the desired
        variant of the Swift runtime libraries.
    """

    _ignore = is_test

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
    ]

    if is_static:
        linkopts.append("-static-libgcc")

    return linkopts

def _swift_toolchain_impl(ctx):
    toolchain_root = ctx.attr.root
    cc_toolchain = find_cpp_toolchain(ctx)

    linker_opts_producer = partial.make(
        _default_linker_opts,
        cc_toolchain,
        ctx.attr.arch,
        ctx.attr.os,
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
    all_files = []
    swift_executable = get_swift_executable_for_toolchain(ctx)
    if swift_executable:
        all_files.append(swift_executable)

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
            all_files = depset(all_files),
            cc_toolchain_info = cc_toolchain,
            cpu = ctx.attr.arch,
            generated_header_module_implicit_deps_providers = (
                collect_implicit_deps_providers([])
            ),
            implicit_deps_providers = (
                collect_implicit_deps_providers([])
            ),
            linker_opts_producer = linker_opts_producer,
            linker_supports_filelist = False,
            object_format = "elf",
            requested_features = requested_features,
            root_dir = toolchain_root,
            supports_objc_interop = False,
            swift_worker = ctx.executable._worker,
            system_name = ctx.attr.os,
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
            "os": attr.string(
                doc = """\
The name of the operating system that this toolchain targets.

This name should match the name used in the toolchain's directory layout for
platform-specific content, such as "linux" in "lib/swift/linux".
""",
                mandatory = True,
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
                cfg = "host",
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

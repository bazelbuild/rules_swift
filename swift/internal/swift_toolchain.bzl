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
load("@bazel_skylib//lib:types.bzl", "types")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(
    ":features.bzl",
    "SWIFT_FEATURE_AUTOLINK_EXTRACT",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "features_for_build_modes",
)
load(":providers.bzl", "SwiftToolchainInfo")
load(":wrappers.bzl", "SWIFT_TOOL_WRAPPER_ATTRIBUTES")

def _default_linker_opts(
        cc_toolchain,
        os,
        toolchain_root,
        is_static,
        is_test):
    """Returns options that should be passed by default to `clang` when linking.

    This function is wrapped in a `partial` that will be propagated as part of the
    toolchain provider. The first three arguments are pre-bound; the `is_static`
    and `is_test` arguments are expected to be passed by the caller.

    Args:
        cc_toolchain: The cpp toolchain from which the `ld` executable is determined.
        os: The operating system name, which is used as part of the library path.
        toolchain_root: The toolchain's root directory.
        is_static: `True` to link against the static version of the Swift runtime, or `False` to
            link against dynamic/shared libraries.
        is_test: `True` if the target being linked is a test target.

    Returns:
        The command line options to pass to `clang` to link against the desired variant of the Swift
        runtime libraries.
    """

    _ignore = is_test

    # TODO(#8): Support statically linking the Swift runtime.
    platform_lib_dir = "{toolchain_root}/lib/swift/{os}".format(
        os = os,
        toolchain_root = toolchain_root,
    )

    linkopts = [
        "-pie",
        "-L{}".format(platform_lib_dir),
        "-Wl,-rpath,{}".format(platform_lib_dir),
        "-lm",
        "-lstdc++",
        "-lrt",
        "-ldl",
    ]

    if is_static:
        linkopts.append("-static-libgcc")

    return linkopts

def _modified_action_args(action_args, toolchain_tools):
    """Updates an argument dictionary with values from a toolchain.

    Args:
        action_args: The `kwargs` dictionary from a call to `actions.run` or `actions.run_shell`.
        toolchain_tools: A `depset` containing toolchain files that must be available to the action
            when it executes (executables and libraries).

    Returns:
        A dictionary that can be passed as the `**kwargs` to a call to one of the action running
        functions that has been modified to include the toolchain values.
    """
    modified_args = dict(action_args)

    # Add the toolchain's tools to the `tools` argument of the action.
    user_tools = modified_args.pop("tools", None)
    if types.is_list(user_tools):
        tools = depset(direct = user_tools, transitive = [toolchain_tools])
    elif type(user_tools) == type(depset()):
        tools = depset(transitive = [user_tools, toolchain_tools])
    elif user_tools:
        fail("'tools' argument must be a sequence or depset.")
    else:
        tools = toolchain_tools
    modified_args["tools"] = tools

    return modified_args

def _run_action(toolchain_tools, actions, **kwargs):
    """Runs an action with the toolchain requirements.

    This is the implementation of the `action_registrars.run` partial, where the first argument is
    pre-bound to a toolchain-specific value.

    Args:
        toolchain_tools: A `depset` containing toolchain files that must be available to the action
            when it executes (executables and libraries).
        actions: The `Actions` object with which to register actions.
        **kwargs: Additional arguments that are passed to `actions.run`.
    """
    modified_args = _modified_action_args(kwargs, toolchain_tools)
    actions.run(**modified_args)

def _run_shell_action(toolchain_tools, actions, **kwargs):
    """Runs a shell action with the toolchain requirements.

    This is the implementation of the `action_registrars.run_shell` partial, where the first
    argument is pre-bound to a toolchain-specific value.

    Args:
        toolchain_tools: A `depset` containing toolchain files that must be available to the action
            when it executes (executables and libraries).
        actions: The `Actions` object with which to register actions.
        **kwargs: Additional arguments that are passed to `actions.run_shell`.
    """
    modified_args = _modified_action_args(kwargs, toolchain_tools)
    actions.run_shell(**modified_args)

def _run_swift_action(toolchain_tools, swift_wrapper, actions, **kwargs):
    """Runs a Swift action with the toolchain requirements.

    This is the implementation of the `action_registrars.run_swift` partial, where
    the first two arguments are pre-bound to toolchain-specific values.

    Args:
      toolchain_tools: A `depset` containing toolchain files that must be
          available to the action when it executes (executables and libraries).
      swift_wrapper: A `File` representing the executable that wraps Swift tool invocations.
      actions: The `Actions` object with which to register actions.
      **kwargs: Additional arguments that are passed to `actions.run`.
    """
    remaining_args = _modified_action_args(kwargs, toolchain_tools)

    # Get the user's arguments. If the caller gave us a list of strings instead of a list of `Args`
    # objects, convert it to a list of `Args` because we're going to create our own `Args` that we
    # prepend to it.
    user_args = remaining_args.pop("arguments", [])
    if user_args and types.is_string(user_args[0]):
        user_args_strings = user_args
        user_args_object = actions.args()
        user_args_object.add_all(user_args_strings)
        user_args = [user_args_object]

    swift_tool = remaining_args.pop("swift_tool")
    wrapper_args = actions.args()
    wrapper_args.add(swift_tool)

    actions.run(
        arguments = [wrapper_args] + user_args,
        executable = swift_wrapper,
        **remaining_args
    )

def _swift_toolchain_impl(ctx):
    toolchain_root = ctx.attr.root
    cc_toolchain = find_cpp_toolchain(ctx)
    cc_toolchain_files = ctx.attr._cc_toolchain.files

    linker_opts_producer = partial.make(
        _default_linker_opts,
        cc_toolchain,
        ctx.attr.os,
        toolchain_root,
    )

    tools = depset(transitive = [ctx.attr._cc_toolchain.files])
    action_registrars = struct(
        run = partial.make(_run_action, tools),
        run_shell = partial.make(_run_shell_action, tools),
        run_swift = partial.make(_run_swift_action, tools, ctx.executable._swift_wrapper),
    )

    # Compute the default requested features and conditional ones based on Xcode version.
    requested_features = features_for_build_modes(ctx)
    requested_features.extend(ctx.features)
    requested_features.append(SWIFT_FEATURE_AUTOLINK_EXTRACT)
    # TODO(#34): Add SWIFT_FEATURE_USE_RESPONSE_FILES based on Swift compiler version.
    # TODO(#35): Add SWIFT_FEATURE_DEBUG_PREFIX_MAP based on Swift compiler version.

    # TODO(allevato): Move some of the remaining hardcoded values, like object
    # format, autolink-extract, and Obj-C interop support, to attributes so that
    # we can remove the assumptions that are only valid on Linux.
    return [
        SwiftToolchainInfo(
            action_environment = {},
            action_registrars = action_registrars,
            cc_toolchain_files = cc_toolchain_files,
            cc_toolchain_info = cc_toolchain,
            clang_executable = ctx.attr.clang_executable,
            command_line_copts = ctx.fragments.swift.copts(),
            cpu = ctx.attr.arch,
            execution_requirements = {},
            implicit_deps = [],
            linker_opts_producer = linker_opts_producer,
            object_format = "elf",
            requested_features = requested_features,
            root_dir = toolchain_root,
            stamp = ctx.attr.stamp,
            supports_objc_interop = False,
            swiftc_copts = [],
            swift_worker = ctx.executable._swift_worker,
            system_name = ctx.attr.os,
            unsupported_features = ctx.disabled_features + [
                SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
            ],
        ),
    ]

swift_toolchain = rule(
    attrs = dicts.add(SWIFT_TOOL_WRAPPER_ATTRIBUTES, {
        "arch": attr.string(
            doc = """
The name of the architecture that this toolchain targets.

This name should match the name used in the toolchain's directory layout for architecture-specific
content, such as "x86_64" in "lib/swift/linux/x86_64".
""",
            mandatory = True,
        ),
        "clang_executable": attr.string(
            doc = """
The path to the `clang` executable, which is used for linking.
""",
            mandatory = True,
        ),
        "os": attr.string(
            doc = """
The name of the operating system that this toolchain targets.

This name should match the name used in the toolchain's directory layout for platform-specific
content, such as "linux" in "lib/swift/linux".
""",
            mandatory = True,
        ),
        "root": attr.string(
            mandatory = True,
        ),
        "stamp": attr.label(
            doc = """
A `CcInfo`-providing target that should be linked into any binaries that are built with stamping
enabled.
""",
            providers = [[CcInfo]],
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
            doc = """
The C++ toolchain from which other tools needed by the Swift toolchain (such as
`clang` and `ar`) will be retrieved.
""",
        ),
    }),
    doc = "Represents a Swift compiler toolchain.",
    fragments = ["swift"],
    implementation = _swift_toolchain_impl,
)

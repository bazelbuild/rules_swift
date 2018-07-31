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

load(":providers.bzl", "SwiftToolchainInfo")
load("@bazel_skylib//:lib.bzl", "dicts", "partial")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

def _default_linker_opts(
        apple_fragment,
        apple_toolchain,
        platform,
        target,
        is_static,
        is_test):
    """Returns options that should be passed by default to `clang` when linking.

    This function is wrapped in a `partial` that will be propagated as part of the toolchain
    provider. The first four arguments are pre-bound; the `is_static` and `is_test` arguments are
    expected to be passed by the caller.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        platform: The `apple_platform` value describing the target platform.
        target: The target triple.
        is_static: `True` to link against the static version of the Swift runtime, or `False` to
            link against dynamic/shared libraries.
        is_test: `True` if the target being linked is a test target.

    Returns:
        The command line options to pass to `clang` to link against the desired variant of the Swift
        runtime libraries.
    """
    platform_framework_dir = apple_toolchain.platform_developer_framework_dir(apple_fragment)
    linkopts = []

    if is_static:
        swift_subdir = "swift_static"
        linkopts.extend([
            "-Wl,-force_load_swift_libs",
            "-framework",
            "Foundation",
            "-lstdc++",
        ])
    else:
        swift_subdir = "swift"

    swift_lib_dir = (
        "{developer_dir}/Toolchains/{toolchain}.xctoolchain/usr/lib/{swift_subdir}/{platform}"
    ).format(
        developer_dir = apple_toolchain.developer_dir(),
        platform = platform.name_in_plist.lower(),
        swift_subdir = swift_subdir,
        toolchain = "XcodeDefault",
    )

    linkopts.extend([
        "-F{}".format(platform_framework_dir),
        "-L{}".format(swift_lib_dir),
        # TODO(b/112000244): These should get added by the C++ Skylark API, but we're using the
        # "c++-link-executable" action right now instead of "objc-executable" because the latter
        # requires additional variables not provided by cc_common. Figure out how to handle this
        # correctly.
        "-ObjC",
        "-Wl,-objc_abi_version,2",
    ])

    # XCTest.framework only lives in the Xcode bundle (its platform framework
    # directory), so test binaries need to have that directory explicitly added to
    # their rpaths.
    if is_test:
        linkopts.append("-Wl,-rpath,{}".format(platform_framework_dir))

    return linkopts

def _default_swiftc_copts(apple_fragment, apple_toolchain, target):
    """Returns options that should be passed by default to `swiftc`.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        target: The target triple.

    Returns:
        A list of options that will be passed to any compile action created by this toolchain.
    """
    copts = [
        "-target",
        target,
        "-sdk",
        apple_toolchain.sdk_dir(),
        "-F",
        apple_toolchain.platform_developer_framework_dir(apple_fragment),
    ]

    bitcode_mode = str(apple_fragment.bitcode_mode)
    if bitcode_mode == "embedded":
        copts.append("-embed-bitcode")
    elif bitcode_mode == "embedded_markers":
        copts.append("-embed-bitcode-marker")
    elif bitcode_mode != "none":
        fail("Internal error: expected apple_fragment.bitcode_mode to be one of: " +
             "['embedded', 'embedded_markers', 'none']")

    return copts

def _is_macos(platform):
    """Returns `True` if the given platform is macOS.

    Args:
        platform: An `apple_platform` value describing the platform for which a
            target is being built.

    Returns:
      `True` if the given platform is macOS.
    """
    return platform.platform_type == apple_common.platform_type.macos

def _modified_action_args(
        action_args,
        toolchain_env,
        toolchain_execution_requirements):
    """Updates an argument dictionary with values from a toolchain.

    Args:
        action_args: The `kwargs` dictionary from a call to `actions.run` or `actions.run_shell`.
        toolchain_env: The required environment from the toolchain.
        toolchain_execution_requirements: The required execution requirements from the toolchain.

    Returns:
        A dictionary that can be passed as the `**kwargs` to a call to one of the action running
        functions that has been modified to include the toolchain values.
    """
    modified_args = dict(action_args)

    # Note that we add the toolchain values second; we do not want the caller to ever be able to
    # override those values. Note also that passing the default to `get` does not always work
    # because `None` could be explicitly a value in the dictionary.
    modified_args["env"] = dicts.add(modified_args.get("env") or {}, toolchain_env)
    modified_args["execution_requirements"] = dicts.add(
        modified_args.get("execution_requirements") or {},
        toolchain_execution_requirements,
    )

    return modified_args

def _run_action(
        toolchain_env,
        toolchain_execution_requirements,
        wrapper,
        actions,
        **kwargs):
    """Runs an action with the toolchain requirements.

    This is the implementation of the `action_registrars.run` partial, where the first three
    arguments are pre-bound to toolchain-specific values.

    Args:
        toolchain_env: The required environment from the toolchain.
        toolchain_execution_requirements: The required execution requirements from the toolchain.
        wrapper: A `File` representing the wrapper executable for the action.
        actions: The `Actions` object with which to register actions.
        **kwargs: Additional arguments that are passed to `actions.run`.
    """
    remaining_args = _modified_action_args(kwargs, toolchain_env, toolchain_execution_requirements)

    # Get the user's arguments. If the caller gave us a list of strings instead of a list of `Args`
    # objects, convert it to a list of `Args` because we're going to create our own `Args` that we
    # prepend to it.
    user_args = remaining_args.pop("arguments", [])
    if user_args and type(user_args[0]) == type(""):
        user_args_strings = user_args
        user_args_object = actions.args()
        user_args_object.add_all(user_args_strings)
        user_args = [user_args_object]

    # Since we're executing the wrapper, make the user's desired executable the first argument to
    # it.
    user_executable = remaining_args.pop("executable")
    wrapper_args = actions.args()
    wrapper_args.add(user_executable)

    # We also need to include the user executable in the "tools" argument of the action, since it
    # won't be referenced by "executable" anymore.
    user_tools = remaining_args.pop("tools", None)
    if type(user_tools) == type([]):
        tools = [user_executable] + user_tools
    elif type(user_tools) == type(depset()):
        tools = depset(direct = [user_executable], transitive = [user_tools])
    elif user_tools:
        fail("'tools' argument must be a sequence or depset.")
    elif type(user_executable) != type(""):
        # Only add the user_executable to the "tools" list if it's a File, not a string.
        tools = [user_executable]
    else:
        tools = []

    actions.run(
        arguments = [wrapper_args] + user_args,
        executable = wrapper,
        tools = tools,
        **remaining_args
    )

def _run_shell_action(
        toolchain_env,
        toolchain_execution_requirements,
        wrapper,
        actions,
        **kwargs):
    """Runs a shell action with the toolchain requirements.

    This is the implementation of the `action_registrars.run_shell` partial, where the first three
    arguments are pre-bound to toolchain-specific values.

    Args:
        toolchain_env: The required environment from the toolchain.
        toolchain_execution_requirements: The required execution requirements from the toolchain.
        wrapper: A `File` representing the wrapper executable for the action.
        actions: The `Actions` object with which to register actions.
        **kwargs: Additional arguments that are passed to `actions.run_shell`.
    """
    remaining_args = _modified_action_args(kwargs, toolchain_env, toolchain_execution_requirements)

    # We need to add the wrapper to the tools of the action so that we can reference its path in the
    # new command line.
    user_tools = remaining_args.pop("tools", [])
    if type(user_tools) == type([]):
        tools = [wrapper] + user_tools
    elif type(user_tools) == type(depset()):
        tools = depset(direct = [wrapper], transitive = [user_tools])
    elif user_tools:
        fail("'tools' argument must be a sequence or depset.")

    # Prepend the wrapper executable to the command being executed.
    user_command = remaining_args.pop("command", "")
    if type(user_command) == type([]):
        command = [wrapper.path] + user_command
    else:
        command = "{wrapper_path} {user_command}".format(
            user_command = user_command,
            wrapper_path = wrapper.path,
        )

    actions.run_shell(
        command = command,
        tools = tools,
        **remaining_args
    )

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

    return "{cpu}-apple-{platform}{version}".format(
        cpu = cpu,
        platform = platform_string,
        version = version,
    )

def _xcode_env(xcode_config, platform):
    """Returns a dictionary containing Xcode-related environment variables.

    Args:
        xcode_config: The `XcodeVersionConfig` provider that contains information about the current
            Xcode configuration.
        platform: The `apple_platform` value describing the target platform being built.

    Returns:
        A `dict` containing Xcode-related environment variables that should be passed to Swift
        compile and link actions.
    """
    return dicts.add(
        apple_common.apple_host_system_env(xcode_config),
        apple_common.target_apple_env(xcode_config, platform),
    )

def _xcode_swift_toolchain_impl(ctx):
    apple_fragment = ctx.fragments.apple
    apple_toolchain = apple_common.apple_toolchain()

    cpu = apple_fragment.single_arch_cpu
    platform = apple_fragment.single_arch_platform
    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]

    target_os_version = xcode_config.minimum_os_for_platform_type(platform.platform_type)
    target = _swift_apple_target_triple(cpu, platform, target_os_version)

    linker_opts_producer = partial.make(
        _default_linker_opts,
        apple_fragment,
        apple_toolchain,
        platform,
        target,
    )
    swiftc_copts = _default_swiftc_copts(apple_fragment, apple_toolchain, target)

    # Configure the action registrars that automatically prepend xcrunwrapper to registered actions.
    env = _xcode_env(xcode_config, platform)
    execution_requirements = {"requires-darwin": ""}
    wrapper = ctx.executable._xcrunwrapper
    action_registrars = struct(
        run = partial.make(_run_action, env, execution_requirements, wrapper),
        run_shell = partial.make(_run_shell_action, env, execution_requirements, wrapper),
    )

    cc_toolchain = find_cpp_toolchain(ctx)

    return [
        SwiftToolchainInfo(
            action_environment = env,
            action_registrars = action_registrars,
            cc_toolchain_info = cc_toolchain,
            clang_executable = None,
            cpu = cpu,
            execution_requirements = execution_requirements,
            implicit_deps = [],
            linker_opts_producer = linker_opts_producer,
            object_format = "macho",
            requires_autolink_extract = False,
            requires_workspace_relative_module_maps = False,
            root_dir = None,
            stamp = ctx.attr.stamp if _is_macos(platform) else None,
            # TODO(#35): Set to True based on Xcode version once
            # https://github.com/apple/swift/pull/17665 makes it into a release.
            supports_debug_prefix_map = False,
            supports_objc_interop = True,
            # TODO(#34): Set to True based on Xcode version once
            # https://github.com/apple/swift/pull/16362 makes it into a release.
            supports_response_files = False,
            swiftc_copts = swiftc_copts,
            system_name = "darwin",
        ),
    ]

xcode_swift_toolchain = rule(
    attrs = {
        "stamp": attr.label(
            doc = """
A `cc`-providing target that should be linked into any binaries that are built
with stamping enabled.
""",
            providers = [["cc"]],
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
            doc = """
The C++ toolchain from which linking flags and other tools needed by the Swift toolchain (such as
`clang`) will be retrieved.
""",
        ),
        "_xcode_config": attr.label(
            default = configuration_field(
                name = "xcode_config_label",
                fragment = "apple",
            ),
        ),
        "_xcrunwrapper": attr.label(
            cfg = "host",
            default = Label("@bazel_tools//tools/objc:xcrunwrapper"),
            executable = True,
        ),
    },
    doc = "Represents a Swift compiler toolchain provided by Xcode.",
    fragments = [
        "apple",
        "cpp",
    ],
    implementation = _xcode_swift_toolchain_impl,
)

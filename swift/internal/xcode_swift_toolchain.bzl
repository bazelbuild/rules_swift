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
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(
    ":features.bzl",
    "SWIFT_FEATURE_AUTOLINK_EXTRACT",
    "SWIFT_FEATURE_BUNDLED_XCTESTS",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
)
load(":providers.bzl", "SwiftToolchainInfo")
load(":wrappers.bzl", "SWIFT_TOOL_WRAPPER_ATTRIBUTES")

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

def _is_xcode_at_least_version(xcode_config, desired_version):
    """Returns True if we are building with at least the given Xcode version.

    Args:
        xcode_config: the `apple_common.XcodeVersionConfig` provider.
        desired_version: The minimum desired Xcode version, as a dotted version string.

    Returns:
        True if the current target is being built with a version of Xcode at least as high as the
        given version.
    """
    current_version = xcode_config.xcode_version()
    if not current_version:
        fail("Could not determine Xcode version at all. This likely means Xcode isn't " +
             "available; if you think this is a mistake, please file an issue.")

    desired_version_value = apple_common.dotted_version(desired_version)
    return current_version >= desired_version_value

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
        bazel_xcode_wrapper,
        actions,
        **kwargs):
    """Runs an action with the toolchain requirements.

    This is the implementation of the `action_registrars.run` partial, where the first three
    arguments are pre-bound to toolchain-specific values.

    Args:
        toolchain_env: The required environment from the toolchain.
        toolchain_execution_requirements: The required execution requirements from the toolchain.
        bazel_xcode_wrapper: A `File` representing the Bazel Xcode wrapper executable for the
            action.
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
    wrapper_args.add("/usr/bin/xcrun")
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
        executable = bazel_xcode_wrapper,
        tools = tools,
        **remaining_args
    )

def _run_shell_action(
        toolchain_env,
        toolchain_execution_requirements,
        bazel_xcode_wrapper,
        actions,
        **kwargs):
    """Runs a shell action with the toolchain requirements.

    This is the implementation of the `action_registrars.run_shell` partial, where the first three
    arguments are pre-bound to toolchain-specific values.

    Args:
        toolchain_env: The required environment from the toolchain.
        toolchain_execution_requirements: The required execution requirements from the toolchain.
        bazel_xcode_wrapper: A `File` representing the Bazel Xcode wrapper executable for the
            action.
        actions: The `Actions` object with which to register actions.
        **kwargs: Additional arguments that are passed to `actions.run_shell`.
    """
    remaining_args = _modified_action_args(kwargs, toolchain_env, toolchain_execution_requirements)

    # We need to add the wrapper to the tools of the action so that we can reference its path in the
    # new command line.
    user_tools = remaining_args.pop("tools", [])
    if type(user_tools) == type([]):
        tools = [bazel_xcode_wrapper] + user_tools
    elif type(user_tools) == type(depset()):
        tools = depset(direct = [bazel_xcode_wrapper], transitive = [user_tools])
    elif user_tools:
        fail("'tools' argument must be a sequence or depset.")

    # Prepend the wrapper executable to the command being executed.
    user_command = remaining_args.pop("command", "")
    if type(user_command) == type([]):
        command = [bazel_xcode_wrapper.path, "/usr/bin/xcrun"] + user_command
    else:
        command = "{wrapper_path} /usr/bin/xcrun {user_command}".format(
            user_command = user_command,
            wrapper_path = bazel_xcode_wrapper.path,
        )

    actions.run_shell(
        command = command,
        tools = tools,
        **remaining_args
    )

def _run_swift_action(
        toolchain_env,
        toolchain_execution_requirements,
        bazel_xcode_wrapper,
        swift_wrapper,
        actions,
        **kwargs):
    """Runs a Swift tool with the toolchain requirements.

    This is the implementation of the `action_registrars.run_swift` partial, where the first four
    arguments are pre-bound to toolchain-specific values.

    Args:
        toolchain_env: The required environment from the toolchain.
        toolchain_execution_requirements: The required execution requirements from the toolchain.
        bazel_xcode_wrapper: A `File` representing the Bazel Xcode wrapper executable for the
            action.
        swift_wrapper: A `File` representing the executable that wraps Swift tool invocations.
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

    # The ordering that we want is `<bazel wrapper> <swift wrapper> xcrun <swift tool>`. This
    # ensures that we ask `xcrun` to run the correct tool instead of having it get picked up
    # from the system path.
    swift_tool = remaining_args.pop("swift_tool")
    wrapper_args = actions.args()
    wrapper_args.add(swift_wrapper)
    wrapper_args.add("/usr/bin/xcrun")
    wrapper_args.add(swift_tool)

    # We also need to include the Swift wrapper in the "tools" argument of the action.
    user_tools = remaining_args.pop("tools", None)
    if type(user_tools) == type([]):
        tools = [swift_wrapper] + user_tools
    elif type(user_tools) == type(depset()):
        tools = depset(direct = [swift_wrapper], transitive = [user_tools])
    elif user_tools:
        fail("'tools' argument must be a sequence or depset.")
    else:
        # Only add the user_executable to the "tools" list if it's a File, not a string.
        tools = [swift_wrapper]

    actions.run(
        arguments = [wrapper_args] + user_args,
        executable = bazel_xcode_wrapper,
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
    bazel_xcode_wrapper = ctx.executable._bazel_xcode_wrapper
    action_registrars = struct(
        run = partial.make(_run_action, env, execution_requirements, bazel_xcode_wrapper),
        run_shell = partial.make(
            _run_shell_action,
            env,
            execution_requirements,
            bazel_xcode_wrapper,
        ),
        run_swift = partial.make(
            _run_swift_action,
            env,
            execution_requirements,
            bazel_xcode_wrapper,
            ctx.executable._swift_wrapper,
        ),
    )

    cc_toolchain = find_cpp_toolchain(ctx)

    # Compute the default requested features based on Xcode version. Xcode 10.0 implies Swift 4.2.
    requested_features = ctx.features + [SWIFT_FEATURE_BUNDLED_XCTESTS]
    if _is_xcode_at_least_version(xcode_config, "10.0"):
        requested_features.append(SWIFT_FEATURE_ENABLE_BATCH_MODE)
        requested_features.append(SWIFT_FEATURE_USE_RESPONSE_FILES)

    # TODO(#35): Add SWIFT_FEATURE_DEBUG_PREFIX_MAP based on Xcode version once
    # https://github.com/apple/swift/pull/17665 makes it into a release.

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
            requested_features = requested_features,
            root_dir = None,
            stamp = ctx.attr.stamp if _is_macos(platform) else None,
            supports_objc_interop = True,
            swiftc_copts = swiftc_copts,
            system_name = "darwin",
            unsupported_features = ctx.disabled_features + [
                SWIFT_FEATURE_AUTOLINK_EXTRACT,
                SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
            ],
        ),
    ]

xcode_swift_toolchain = rule(
    attrs = dicts.add(SWIFT_TOOL_WRAPPER_ATTRIBUTES, {
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
        "_bazel_xcode_wrapper": attr.label(
            cfg = "host",
            default = Label(
                "@build_bazel_rules_swift//tools/wrappers:bazel_xcode_wrapper",
            ),
            executable = True,
        ),
    }),
    doc = "Represents a Swift compiler toolchain provided by Xcode.",
    fragments = [
        "apple",
        "cpp",
    ],
    implementation = _xcode_swift_toolchain_impl,
)

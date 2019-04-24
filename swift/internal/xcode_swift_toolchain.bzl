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

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:types.bzl", "types")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(
    ":features.bzl",
    "SWIFT_FEATURE_AUTOLINK_EXTRACT",
    "SWIFT_FEATURE_BUNDLED_XCTESTS",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
    "features_for_build_modes",
)
load(":providers.bzl", "SwiftToolchainInfo")
load(":wrappers.bzl", "SWIFT_TOOL_WRAPPER_ATTRIBUTES")

def _command_line_objc_copts(objc_fragment):
    """Returns copts that should be passed to `clang` from the `objc` fragment.

    Args:
        objc_fragment: The `objc` configuration fragment.

    Returns:
        A list of `clang` copts, each of which is preceded by `-Xcc` so that they can be passed
        through `swiftc` to its underlying ClangImporter instance.
    """

    # In general, every compilation mode flag from native `objc_*` rules should be passed, but `-g`
    # seems to break Clang module compilation. Since this flag does not make much sense for module
    # compilation and only touches headers, it's ok to omit.
    clang_copts = objc_fragment.copts + objc_fragment.copts_for_current_compilation_mode
    return collections.before_each("-Xcc", [copt for copt in clang_copts if copt != "-g"])

def _default_linker_opts(
        apple_fragment,
        apple_toolchain,
        platform,
        target,
        xcode_config,
        is_static,
        is_test):
    """Returns options that should be passed by default to `clang` when linking.

    This function is wrapped in a `partial` that will be propagated as part of the toolchain
    provider. The first five arguments are pre-bound; the `is_static` and `is_test` arguments are
    expected to be passed by the caller.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        platform: The `apple_platform` value describing the target platform.
        target: The target triple.
        xcode_config: The Xcode configuration.
        is_static: `True` to link against the static version of the Swift runtime, or `False` to
            link against dynamic/shared libraries.
        is_test: `True` if the target being linked is a test target.

    Returns:
        The command line options to pass to `clang` to link against the desired variant of the Swift
        runtime libraries.
    """
    platform_framework_dir = apple_toolchain.platform_developer_framework_dir(apple_fragment)
    linkopts = []

    uses_runtime_in_os = _is_xcode_at_least_version(xcode_config, "10.2")
    if uses_runtime_in_os:
        # Starting with Xcode 10.2, Apple forbids statically linking to the Swift runtime. The
        # libraries are distributed with the OS and located in /usr/lib/swift.
        swift_subdir = "swift"
        linkopts.append("-Wl,-rpath,/usr/lib/swift")
    elif is_static:
        # This branch and the branch below now only support Xcode 10.1 and below. Eventually,
        # once we drop support for those versions, they can be deleted.
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

    # TODO(b/128303533): It's possible to run Xcode 10.2 on a version of macOS 10.14.x that does
    # not yet include `/usr/lib/swift`. Later Xcode 10.2 betas have deleted the `swift_static`
    # directory, so we must manually add the dylibs to the binary's rpath or those binaries won't
    # be able to run at all. This is added after `/usr/lib/swift` above so the system versions
    # will always be preferred if they are present.
    # This workaround can be removed once Xcode 10.2 and macOS 10.14.4 are out of beta.
    if uses_runtime_in_os and platform == apple_common.platform.macos:
        linkopts.append("-Wl,-rpath,{}".format(swift_lib_dir))

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

def _trim_version(version):
    """Trim the given version number down to a maximum of three components.

    Args:
        version: The version number to trim; either a string or a `DottedVersion` value.

    Returns:
        The trimmed version number as a `DottedVersion` value.
    """
    version = str(version)
    parts = version.split(".")
    maxparts = min(len(parts), 3)
    return apple_common.dotted_version(".".join(parts[:maxparts]))

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

    # TODO(b/131195460): DottedVersion comparison is broken for four-component versions that are
    # returned by modern Xcodes. Work around it for now.
    desired_version_value = _trim_version(desired_version)
    return _trim_version(current_version) >= desired_version_value

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
    if user_args and types.is_string(user_args[0]):
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
    if types.is_list(user_tools):
        tools = [user_executable] + user_tools
    elif type(user_tools) == type(depset()):
        tools = depset(direct = [user_executable], transitive = [user_tools])
    elif user_tools:
        fail("'tools' argument must be a sequence or depset.")
    elif not types.is_string(user_executable):
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
    if types.is_list(user_tools):
        tools = [bazel_xcode_wrapper] + user_tools
    elif type(user_tools) == type(depset()):
        tools = depset(direct = [bazel_xcode_wrapper], transitive = [user_tools])
    else:
        fail("'tools' argument must be a sequence or depset.")

    # Prepend the wrapper executable to the command being executed.
    user_command = remaining_args.pop("command", "")
    if types.is_list(user_command):
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
    if user_args and types.is_string(user_args[0]):
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
    if types.is_list(user_tools):
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
        xcode_config,
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
    cc_toolchain_files = ctx.attr._cc_toolchain.files

    # Compute the default requested features and conditional ones based on Xcode version.
    requested_features = features_for_build_modes(ctx, objc_fragment = ctx.fragments.objc)
    requested_features.extend(ctx.features)
    requested_features.append(SWIFT_FEATURE_BUNDLED_XCTESTS)

    # Xcode 10.0 implies Swift 4.2.
    if _is_xcode_at_least_version(xcode_config, "10.0"):
        requested_features.append(SWIFT_FEATURE_ENABLE_BATCH_MODE)
        requested_features.append(SWIFT_FEATURE_USE_RESPONSE_FILES)

    # Xcode 10.2 implies Swift 5.0.
    if _is_xcode_at_least_version(xcode_config, "10.2"):
        requested_features.append(SWIFT_FEATURE_DEBUG_PREFIX_MAP)

    command_line_copts = _command_line_objc_copts(ctx.fragments.objc) + ctx.fragments.swift.copts()

    return [
        SwiftToolchainInfo(
            action_environment = env,
            action_registrars = action_registrars,
            cc_toolchain_files = cc_toolchain_files,
            cc_toolchain_info = cc_toolchain,
            clang_executable = None,
            command_line_copts = command_line_copts,
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
            swift_worker = ctx.executable._swift_worker,
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
A `CcInfo`-providing target that should be linked into any binaries that are built with stamping
enabled.
""",
            providers = [[CcInfo]],
        ),
        "_bazel_xcode_wrapper": attr.label(
            cfg = "host",
            default = Label(
                "@build_bazel_rules_swift//tools/wrappers:bazel_xcode_wrapper",
            ),
            executable = True,
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
    }),
    doc = "Represents a Swift compiler toolchain provided by Xcode.",
    fragments = [
        "apple",
        "objc",
        "swift",
    ],
    implementation = _xcode_swift_toolchain_impl,
)

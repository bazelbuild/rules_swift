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
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(":actions.bzl", "swift_action_names")
load(":attrs.bzl", "swift_toolchain_driver_attrs")
load(":compiling.bzl", "compile_action_configs")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_BITCODE_EMBEDDED",
    "SWIFT_FEATURE_BITCODE_EMBEDDED_MARKERS",
    "SWIFT_FEATURE_BUNDLED_XCTESTS",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
)
load(":features.bzl", "features_for_build_modes")
load(":toolchain_config.bzl", "swift_toolchain_config")
load(":providers.bzl", "SwiftToolchainInfo")
load(":utils.bzl", "get_swift_executable_for_toolchain")

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

def _command_line_objc_copts(objc_fragment):
    """Returns copts that should be passed to `clang` from the `objc` fragment.

    Args:
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
    clang_copts = (
        objc_fragment.copts + objc_fragment.copts_for_current_compilation_mode
    )
    return collections.before_each(
        "-Xcc",
        [copt for copt in clang_copts if copt != "-g"],
    )

def _default_linker_opts(
        apple_fragment,
        apple_toolchain,
        platform,
        target,
        xcode_config,
        is_static,
        is_test):
    """Returns options that should be passed by default to `clang` when linking.

    This function is wrapped in a `partial` that will be propagated as part of
    the toolchain provider. The first five arguments are pre-bound; the
    `is_static` and `is_test` arguments are expected to be passed by the caller.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        platform: The `apple_platform` value describing the target platform.
        target: The target triple.
        xcode_config: The Xcode configuration.
        is_static: `True` to link against the static version of the Swift
            runtime, or `False` to link against dynamic/shared libraries.
        is_test: `True` if the target being linked is a test target.

    Returns:
        The command line options to pass to `clang` to link against the desired
        variant of the Swift runtime libraries.
    """
    platform_framework_dir = apple_toolchain.platform_developer_framework_dir(
        apple_fragment,
    )
    linkopts = []

    uses_runtime_in_os = _is_xcode_at_least_version(xcode_config, "10.2")
    if uses_runtime_in_os:
        # Starting with Xcode 10.2, Apple forbids statically linking to the
        # Swift runtime. The libraries are distributed with the OS and located
        # in /usr/lib/swift.
        swift_subdir = "swift"
        linkopts.append("-Wl,-rpath,/usr/lib/swift")
    elif is_static:
        # This branch and the branch below now only support Xcode 10.1 and
        # below. Eventually, once we drop support for those versions, they can
        # be deleted.
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
        "{developer_dir}/Toolchains/{toolchain}.xctoolchain/" +
        "usr/lib/{swift_subdir}/{platform}"
    ).format(
        developer_dir = apple_toolchain.developer_dir(),
        platform = platform.name_in_plist.lower(),
        swift_subdir = swift_subdir,
        toolchain = "XcodeDefault",
    )

    # TODO(b/128303533): It's possible to run Xcode 10.2 on a version of macOS
    # 10.14.x that does not yet include `/usr/lib/swift`. Later Xcode 10.2 betas
    # have deleted the `swift_static` directory, so we must manually add the
    # dylibs to the binary's rpath or those binaries won't be able to run at
    # all. This is added after `/usr/lib/swift` above so the system versions
    # will always be preferred if they are present. This workaround can be
    # removed once Xcode 10.2 and macOS 10.14.4 are out of beta.
    if uses_runtime_in_os and platform == apple_common.platform.macos:
        linkopts.append("-Wl,-rpath,{}".format(swift_lib_dir))

    linkopts.extend([
        "-F{}".format(platform_framework_dir),
        "-L{}".format(swift_lib_dir),
        # TODO(b/112000244): These should get added by the C++ Skylark API, but
        # we're using the "c++-link-executable" action right now instead of
        # "objc-executable" because the latter requires additional variables not
        # provided by cc_common. Figure out how to handle this correctly.
        "-ObjC",
        "-Wl,-objc_abi_version,2",
    ])

    use_system_swift_libs = _is_xcode_at_least_version(xcode_config, "11.0")
    if use_system_swift_libs:
        linkopts.append("-L/usr/lib/swift")

    # XCTest.framework only lives in the Xcode bundle (its platform framework
    # directory), so test binaries need to have that directory explicitly added
    # to their rpaths.
    if is_test:
        linkopts.extend([
            "-Wl,-rpath,{}".format(platform_framework_dir),
            "-L{}".format(_swift_developer_lib_dir(platform_framework_dir)),
        ])

    return linkopts

def _features_for_bitcode_mode(bitcode_mode):
    """Gets the list of features to enable for the selected Bitcode mode.

    Args:
        bitcode_mode: The `bitcode_mode` value from the Apple configuration
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

def _resource_directory_configurator(developer_dir, prerequisites, args):
    """Configures compiler flags about the toolchain's resource directory.

    We must pass a resource directory explicitly if the build rules are invoked
    using a custom driver executable or a partial toolchain root, so that the
    compiler doesn't try to find its resources relative to that binary.

    Args:
        developer_dir: The path to Xcode's Developer directory. This argument is
            pre-bound in the partial.
        prerequisites: The value returned by
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
        apple_fragment,
        apple_toolchain,
        needs_resource_directory,
        target_triple):
    """Returns the action configurations for the Swift toolchain.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        needs_resource_directory: If True, the toolchain needs the resource
            directory passed explicitly to the compiler.
        target_triple: The target triple.

    Returns:
        The action configurations for the Swift toolchain.
    """
    developer_dir = apple_toolchain.developer_dir()
    platform_framework_dir = (
        apple_toolchain.platform_developer_framework_dir(apple_fragment)
    )
    sdk_dir = apple_toolchain.sdk_dir()

    action_configs = [
        # Basic compilation flags (target triple and toolchain search paths).
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-target", target_triple),
                swift_toolchain_config.add_arg("-sdk", sdk_dir),
                swift_toolchain_config.add_arg(
                    platform_framework_dir,
                    format = "-F%s",
                ),
                swift_toolchain_config.add_arg(
                    _swift_developer_lib_dir(platform_framework_dir),
                    format = "-I%s",
                ),
            ],
        ),

        # Bitcode-related flags.
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [swift_toolchain_config.add_arg("-embed-bitcode")],
            features = [SWIFT_FEATURE_BITCODE_EMBEDDED],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.COMPILE],
            configurators = [
                swift_toolchain_config.add_arg("-embed-bitcode-marker"),
            ],
            features = [SWIFT_FEATURE_BITCODE_EMBEDDED_MARKERS],
        ),
    ]

    if needs_resource_directory:
        # If the user is using a custom driver but not a complete custom
        # toolchain, provide the original toolchain's resources as the resource
        # directory so that modules are found correctly.
        action_configs.append(
            swift_toolchain_config.action_config(
                actions = [swift_action_names.COMPILE],
                configurators = [
                    partial.make(
                        _resource_directory_configurator,
                        developer_dir,
                    ),
                ],
            ),
        )

    action_configs.extend(compile_action_configs())
    return action_configs

def _all_tool_configs(
        custom_toolchain,
        env,
        execution_requirements,
        swift_executable,
        toolchain_root,
        use_param_file):
    """Returns the tool configurations for the Swift toolchain.

    Args:
        custom_toolchain: The bundle identifier of a custom Swift toolchain, if
            one was requested.
        env: The environment variables to set when launching tools.
        execution_requirements: The execution requirements for tools.
        swift_executable: A custom Swift driver executable to be used during the
            build, if provided.
        toolchain_root: The root directory of the toolchain, if provided.
        use_param_file: If True, actions should have their arguments written to
            param files.

    Returns:
        A dictionary mapping action name to tool configuration.
    """

    # Configure the environment variables that the worker needs to fill in the
    # Bazel placeholders for SDK root and developer directory, along with the
    # custom toolchain if requested.
    if custom_toolchain:
        env = dict(env)
        env["TOOLCHAINS"] = custom_toolchain

    return {
        swift_action_names.COMPILE: swift_toolchain_config.driver_tool_config(
            driver_mode = "swiftc",
            env = env,
            execution_requirements = execution_requirements,
            swift_executable = swift_executable,
            toolchain_root = toolchain_root,
            use_param_file = use_param_file,
            worker_mode = "persistent",
        ),
    }

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

def _xcode_execution_requirements(xcode_config):
    """Returns execution requirements for actions involving Xcode.

    Args:
        xcode_config: The Xcode configuration object.

    Returns:
        A dictionary of execution requirements to be passed when registering
        actions.
    """

    # All Swift actions should be executed on Darwin, even if Bazel is running
    # on a non-Darwin host.
    # TODO(steinman): Replace this with xcode_config.execution_info once it is
    # available.
    execution_requirements = {"requires-darwin": ""}
    if xcode_config:
        if xcode_config.availability() == "remote":
            execution_requirements["no-local"] = "1"
        elif xcode_config.availability() == "local":
            execution_requirements["no-remote"] = "1"
        execution_requirements["supports-xcode-requirements-set"] = "1"

    return execution_requirements

def _xcode_swift_toolchain_impl(ctx):
    apple_fragment = ctx.fragments.apple
    apple_toolchain = apple_common.apple_toolchain()
    cc_toolchain = find_cpp_toolchain(ctx)

    cpu = apple_fragment.single_arch_cpu
    platform = apple_fragment.single_arch_platform
    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]

    target_os_version = xcode_config.minimum_os_for_platform_type(
        platform.platform_type,
    )
    target = _swift_apple_target_triple(cpu, platform, target_os_version)

    linker_opts_producer = partial.make(
        _default_linker_opts,
        apple_fragment,
        apple_toolchain,
        platform,
        target,
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
        objc_fragment = ctx.fragments.objc,
    )
    requested_features.extend(ctx.features)
    requested_features.append(SWIFT_FEATURE_BUNDLED_XCTESTS)
    requested_features.extend(
        _features_for_bitcode_mode(apple_fragment.bitcode_mode),
    )

    # Xcode 10.0 implies Swift 4.2.
    if _is_xcode_at_least_version(xcode_config, "10.0"):
        use_param_file = True
        requested_features.append(SWIFT_FEATURE_ENABLE_BATCH_MODE)
        requested_features.append(SWIFT_FEATURE_USE_RESPONSE_FILES)
    else:
        use_param_file = False

    # Xcode 10.2 implies Swift 5.0.
    if _is_xcode_at_least_version(xcode_config, "10.2"):
        requested_features.append(SWIFT_FEATURE_DEBUG_PREFIX_MAP)

    # Xcode 11.0 implies Swift 5.1.
    if _is_xcode_at_least_version(xcode_config, "11.0"):
        requested_features.append(SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION)
        requested_features.append(SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS)

    command_line_copts = (
        _command_line_objc_copts(ctx.fragments.objc) +
        ctx.fragments.swift.copts()
    )

    env = _xcode_env(platform = platform, xcode_config = xcode_config)
    execution_requirements = _xcode_execution_requirements(
        xcode_config = xcode_config,
    )

    all_tool_configs = _all_tool_configs(
        custom_toolchain = custom_toolchain,
        env = env,
        execution_requirements = execution_requirements,
        swift_executable = swift_executable,
        toolchain_root = toolchain_root,
        use_param_file = use_param_file,
    )
    all_action_configs = _all_action_configs(
        apple_fragment = apple_fragment,
        apple_toolchain = apple_toolchain,
        needs_resource_directory = swift_executable or toolchain_root,
        target_triple = target,
    )

    # Xcode toolchains don't pass any files explicitly here because they're
    # just available as part of the Xcode bundle, unless we're being asked to
    # use a custom driver executable.
    all_files = []
    if swift_executable:
        all_files.append(swift_executable)

    return [
        SwiftToolchainInfo(
            action_configs = all_action_configs,
            all_files = depset(all_files),
            cc_toolchain_info = cc_toolchain,
            command_line_copts = command_line_copts,
            cpu = cpu,
            linker_opts_producer = linker_opts_producer,
            object_format = "macho",
            optional_implicit_deps = [],
            requested_features = requested_features,
            required_implicit_deps = [],
            stamp_producer = None,
            supports_objc_interop = True,
            swift_worker = ctx.executable._worker,
            system_name = "darwin",
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
            "_cc_toolchain": attr.label(
                default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
                doc = """\
The C++ toolchain from which linking flags and other tools needed by the Swift
toolchain (such as `clang`) will be retrieved.
""",
            ),
            "_worker": attr.label(
                cfg = "host",
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
        "apple",
        "objc",
        "swift",
    ],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    implementation = _xcode_swift_toolchain_impl,
)

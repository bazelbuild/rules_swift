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
load(
    ":features.bzl",
    "SWIFT_FEATURE_AUTOLINK_EXTRACT",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "features_for_build_modes",
)
load(":providers.bzl", "SwiftToolchainInfo")

def _default_linker_opts(
        cc_toolchain,
        cpu,
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
        cpu: The CPU architecture, which is used as part of the library path.
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

    # Combine build mode features, autoconfigured features, and required features.
    requested_features = features_for_build_modes(ctx)
    requested_features.extend(ctx.features)
    requested_features.append(SWIFT_FEATURE_AUTOLINK_EXTRACT)

    # TODO(allevato): Move some of the remaining hardcoded values, like object format and Obj-C
    # interop support, to attributes so that we can remove the assumptions that are only valid on
    # Linux.
    return [
        SwiftToolchainInfo(
            action_environment = {},
            # Swift.org toolchains assume everything is just available on the
            # PATH and we don't try to pass the toolchain contents here.
            all_files = depset(),
            cc_toolchain_info = cc_toolchain,
            clang_executable = ctx.attr.clang_executable,
            command_line_copts = ctx.fragments.swift.copts(),
            cpu = ctx.attr.arch,
            execution_requirements = {},
            linker_opts_producer = linker_opts_producer,
            object_format = "elf",
            optional_implicit_deps = [],
            requested_features = requested_features,
            required_implicit_deps = [],
            root_dir = toolchain_root,
            stamp_producer = None,
            supports_objc_interop = False,
            swiftc_copts = [],
            swift_worker = ctx.executable._worker,
            system_name = ctx.attr.os,
            unsupported_features = ctx.disabled_features + [
                SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
            ],
        ),
    ]

swift_toolchain = rule(
    attrs = dicts.add({
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
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
            doc = """
The C++ toolchain from which other tools needed by the Swift toolchain (such as
`clang` and `ar`) will be retrieved.
""",
        ),
        "_worker": attr.label(
            cfg = "host",
            allow_files = True,
            default = Label("//tools/worker"),
            doc = """
An executable that wraps Swift compiler invocations and also provides support
for incremental compilation using a persistent mode.
""",
            executable = True,
        ),
    }),
    doc = "Represents a Swift compiler toolchain.",
    fragments = ["swift"],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    implementation = _swift_toolchain_impl,
)

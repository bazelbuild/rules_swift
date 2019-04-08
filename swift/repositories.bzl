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

"""Definitions for handling Bazel repositories used by the Swift rules."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _create_linux_toolchain(repository_ctx):
    """Creates BUILD targets for the Swift toolchain on Linux.

    Args:
      repository_ctx: The repository rule context.
    """
    if repository_ctx.os.environ.get("CC") != "clang":
        fail("ERROR: rules_swift uses Bazel's CROSSTOOL to link, but Swift " +
             "requires that the driver used is clang. Please set `CC=clang` in " +
             "your environment before invoking Bazel.")

    path_to_swiftc = repository_ctx.which("swiftc")
    path_to_clang = repository_ctx.which("clang")
    root = path_to_swiftc.dirname.dirname

    repository_ctx.file(
        "BUILD",
        """
load(
    "@build_bazel_rules_swift//swift/internal:swift_toolchain.bzl",
    "swift_toolchain",
)

package(default_visibility = ["//visibility:public"])

swift_toolchain(
    name = "toolchain",
    arch = "x86_64",
    clang_executable = "{path_to_clang}",
    os = "linux",
    root = "{root}",
)
""".format(
            path_to_clang = path_to_clang,
            root = root,
        ),
    )

def _create_xcode_toolchain(repository_ctx):
    """Creates BUILD targets for the Swift toolchain on macOS using Xcode.

    Args:
      repository_ctx: The repository rule context.
    """
    repository_ctx.file(
        "BUILD",
        """
load(
    "@build_bazel_rules_swift//swift/internal:xcode_swift_toolchain.bzl",
    "xcode_swift_toolchain",
)

package(default_visibility = ["//visibility:public"])

xcode_swift_toolchain(
    name = "toolchain",
)
""",
    )

def _swift_autoconfiguration_impl(repository_ctx):
    # TODO(allevato): This is expedient and fragile. Use the platforms/toolchains
    # APIs instead to define proper toolchains, and make it possible to support
    # non-Xcode toolchains on macOS as well.
    os_name = repository_ctx.os.name.lower()
    if os_name.startswith("mac os"):
        _create_xcode_toolchain(repository_ctx)
    else:
        _create_linux_toolchain(repository_ctx)

_swift_autoconfiguration = repository_rule(
    environ = ["CC", "PATH"],
    implementation = _swift_autoconfiguration_impl,
)

def _maybe(repo_rule, name, **kwargs):
    """Executes the given repository rule if it hasn't been executed already.

    Args:
      repo_rule: The repository rule to be executed (e.g., `http_archive`.)
      name: The name of the repository to be defined by the rule.
      **kwargs: Additional arguments passed directly to the repository rule.
    """
    if not native.existing_rule(name):
        repo_rule(name = name, **kwargs)

def swift_rules_dependencies():
    """Fetches repositories that are dependencies of the `rules_swift` workspace.

    Users should call this macro in their `WORKSPACE` to ensure that all of the
    dependencies of the Swift rules are downloaded and that they are isolated from
    changes to those dependencies.
    """
    _maybe(
        http_archive,
        name = "bazel_skylib",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/0.8.0/bazel-skylib.0.8.0.tar.gz",
        ],
        sha256 = "2ef429f5d7ce7111263289644d233707dba35e39696377ebab8b0bc701f7818e",
    )

    _maybe(
        http_archive,
        name = "build_bazel_apple_support",
        urls = [
            "https://github.com/bazelbuild/apple_support/releases/download/0.6.0/apple_support.0.6.0.tar.gz",
        ],
        sha256 = "7356dbd44dea71570a929d1d4731e870622151a5f27164d966dda97305f33471",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_protobuf",
        urls = ["https://github.com/apple/swift-protobuf/archive/1.4.0.zip"],
        sha256 = "70ed9d031144752f106276d495e854b314d7fab4c3e1cd97150655d882dd0eb6",
        strip_prefix = "swift-protobuf-1.4.0/",
        type = "zip",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_protobuf/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_grpc_grpc_swift",
        urls = ["https://github.com/grpc/grpc-swift/archive/0.8.1.zip"],
        sha256 = "04b797a2d0fe03687768f5c503917f418d7612b950ec89919f0a8e3cb70b7a43",
        strip_prefix = "grpc-swift-0.8.1/",
        type = "zip",
        build_file = "@build_bazel_rules_swift//third_party:com_github_grpc_grpc_swift/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_nlohmann_json",
        urls = ["https://github.com/nlohmann/json/releases/download/v3.6.1/include.zip"],
        sha256 = "69cc88207ce91347ea530b227ff0776db82dcb8de6704e1a3d74f4841bc651cf",
        type = "zip",
        build_file = "@build_bazel_rules_swift//third_party:com_github_nlohmann_json/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_google_protobuf",
        # v3.7.1, latest as of 2019-04-03
        urls = ["https://github.com/protocolbuffers/protobuf/archive/v3.7.1.zip"],
        sha256 = "f976a4cd3f1699b6d20c1e944ca1de6754777918320c719742e1674fcf247b7e",
        strip_prefix = "protobuf-3.7.1",
        type = "zip",
    )

    # TODO(https://github.com/protocolbuffers/protobuf/issues/5918):
    # Remove this when protobuf releases protobuf_deps.bzl and instruct users to call
    # `protobuf_deps()` instead.
    if not native.existing_rule("net_zlib"):
        http_archive(
            name = "net_zlib",
            build_file = "@com_google_protobuf//examples:third_party/zlib.BUILD",
            sha256 = "c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1",
            strip_prefix = "zlib-1.2.11",
            urls = ["https://zlib.net/zlib-1.2.11.tar.gz"],
        )

        native.bind(
            name = "zlib",
            actual = "@net_zlib//:zlib",
        )

    _maybe(
        _swift_autoconfiguration,
        name = "build_bazel_rules_swift_local_config",
    )

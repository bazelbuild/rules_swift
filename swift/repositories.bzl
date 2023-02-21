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
load(
    "@build_bazel_rules_swift//swift/internal:swift_autoconfiguration.bzl",
    "swift_autoconfiguration",
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

def swift_rules_dependencies(include_bzlmod_ready_dependencies = True):
    """Fetches repositories that are dependencies of `rules_swift`.

    Users should call this macro in their `WORKSPACE` to ensure that all of the
    dependencies of the Swift rules are downloaded and that they are isolated
    from changes to those dependencies.

    Args:
        include_bzlmod_ready_dependencies: Whether or not bzlmod-ready
            dependencies should be included.
    """
    if include_bzlmod_ready_dependencies:
        _maybe(
            http_archive,
            name = "bazel_skylib",
            urls = [
                "https://github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
                "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
            ],
            sha256 = "74d544d96f4a5bb630d465ca8bbcfe231e3594e5aae57e1edbf17a6eb3ca2506",
        )

        _maybe(
            http_archive,
            name = "build_bazel_apple_support",
            urls = [
                "https://github.com/bazelbuild/apple_support/releases/download/1.4.1/apple_support.1.4.1.tar.gz",
            ],
            sha256 = "77a121a0f5d4cd88824429464ad2bfb54bdc8a3bccdb4d31a6c846003a3f5e44",
        )

        _maybe(
            http_archive,
            name = "rules_proto",
            urls = [
                "https://github.com/bazelbuild/rules_proto/archive/refs/tags/5.3.0-21.7.tar.gz",
            ],
            sha256 = "dc3fb206a2cb3441b485eb1e423165b231235a1ea9b031b4433cf7bc1fa460dd",
            strip_prefix = "rules_proto-5.3.0-21.7",
        )

        _maybe(
            http_archive,
            name = "com_github_nlohmann_json",
            urls = [
                "https://github.com/nlohmann/json/releases/download/v3.6.1/include.zip",
            ],
            sha256 = "69cc88207ce91347ea530b227ff0776db82dcb8de6704e1a3d74f4841bc651cf",
            type = "zip",
            build_file = "@build_bazel_rules_swift//third_party:com_github_nlohmann_json/BUILD.overlay",
        )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_protobuf",
        urls = ["https://github.com/apple/swift-protobuf/archive/1.20.2.tar.gz"],
        sha256 = "3fb50bd4d293337f202d917b6ada22f9548a0a0aed9d9a4d791e6fbd8a246ebb",
        strip_prefix = "swift-protobuf-1.20.2/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_protobuf/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_grpc_grpc_swift",
        urls = ["https://github.com/grpc/grpc-swift/archive/1.14.0.tar.gz"],
        sha256 = "643109e821be5097082a618b11f0fa6d57f858680d86e88a0e390e94fb85f21d",
        strip_prefix = "grpc-swift-1.14.0/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_grpc_grpc_swift/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio",
        urls = ["https://github.com/apple/swift-nio/archive/2.42.0.tar.gz"],
        sha256 = "e3304bc3fb53aea74a3e54bd005ede11f6dc357117d9b1db642d03aea87194a0",
        strip_prefix = "swift-nio-2.42.0/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_nio/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_http2",
        urls = ["https://github.com/apple/swift-nio-http2/archive/1.24.1.tar.gz"],
        sha256 = "819b9ea605e90c7b00645b83af595909446edac5cb493ae3717c720c7c284514",
        strip_prefix = "swift-nio-http2-1.24.1/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_nio_http2/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_transport_services",
        urls = ["https://github.com/apple/swift-nio-transport-services/archive/1.15.0.tar.gz"],
        sha256 = "f3498dafa633751a52b9b7f741f7ac30c42bcbeb3b9edca6d447e0da8e693262",
        strip_prefix = "swift-nio-transport-services-1.15.0/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_nio_transport_services/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_extras",
        urls = ["https://github.com/apple/swift-nio-extras/archive/1.4.0.tar.gz"],
        sha256 = "4684b52951d9d9937bb3e8ccd6b5daedd777021ef2519ea2f18c4c922843b52b",
        strip_prefix = "swift-nio-extras-1.4.0/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_nio_extras/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_log",
        urls = ["https://github.com/apple/swift-log/archive/1.4.4.tar.gz"],
        sha256 = "48fe66426c784c0c20031f15dc17faf9f4c9037c192bfac2f643f65cb2321ba0",
        strip_prefix = "swift-log-1.4.4/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_log/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_atomics",
        urls = ["https://github.com/apple/swift-atomics/archive/1.0.2.tar.gz"],
        sha256 = "c8b88186db4902dc5109340f4a745ea787cb2aa9533c7e6d1e634549f9e527b1",
        strip_prefix = "swift-atomics-1.0.2/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_atomics/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_collections",
        urls = ["https://github.com/apple/swift-collections/archive/53a8adc54374f620002a3b6401d39e0feb3c57ae.tar.gz"],
        sha256 = "70c382c806cb94c939cecff5873ba1f8f695cb115d2085db855d0441e7122df8",
        strip_prefix = "swift-collections-53a8adc54374f620002a3b6401d39e0feb3c57ae/",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_collections/BUILD.overlay",
    )

    # It relies on `index-import` to import indexes into Bazel's remote
    # cache and allow using a global index internally in workers.
    # Note: this is only loaded if swift.index_while_building_v2 is enabled
    _maybe(
        http_archive,
        name = "build_bazel_rules_swift_index_import",
        build_file = "@build_bazel_rules_swift//third_party:build_bazel_rules_swift_index_import/BUILD.overlay",
        canonical_id = "index-import-5.7.0.1",
        urls = ["https://github.com/MobileNativeFoundation/index-import/releases/download/5.7.0.1/index-import.tar.gz"],
        sha256 = "9e26765efd7cda24dbe91965dfb1ff8abcaa9ac7bafc3afa7fc1d081dea47d7f",
    )

    _maybe(
        swift_autoconfiguration,
        name = "build_bazel_rules_swift_local_config",
    )

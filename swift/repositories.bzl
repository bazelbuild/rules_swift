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
    "//swift/internal:swift_autoconfiguration.bzl",
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

# buildifier: disable=unnamed-macro
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
            url = "https://github.com/bazelbuild/apple_support/releases/download/1.21.0/apple_support.1.21.0.tar.gz",
            sha256 = "293f5fe430787f3a995b2703440d27498523df119de00b84002deac9525bea55",
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
            build_file = Label(
                "//third_party:com_github_nlohmann_json/BUILD.overlay",
            ),
        )

        _maybe(
            http_archive,
            name = "bazel_features",
            sha256 = "53182a68f172a2af4ad37051f82201e222bc19f7a40825b877da3ff4c922b9e0",
            strip_prefix = "bazel_features-1.3.0",
            url = "https://github.com/bazel-contrib/bazel_features/releases/download/v1.3.0/bazel_features-v1.3.0.tar.gz",
        )

        _maybe(
            http_archive,
            name = "com_github_apple_swift_argument_parser",
            urls = ["https://github.com/apple/swift-argument-parser/archive/refs/tags/1.3.0.tar.gz"],
            sha256 = "e5010ff37b542807346927ba68b7f06365a53cf49d36a6df13cef50d86018204",
            strip_prefix = "swift-argument-parser-1.3.0",
            build_file = Label(
                "//third_party:com_github_apple_swift_argument_parser/BUILD.overlay",
            ),
        )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_protobuf",
        urls = ["https://github.com/apple/swift-protobuf/archive/1.28.1.tar.gz"],  # pinned to grpc-swift version
        sha256 = "9204c512ee90378f22db3255ecc35de927d672a4925d5222497c57b3f30de726",
        strip_prefix = "swift-protobuf-1.28.1/",
        build_file = Label(
            "//third_party:com_github_apple_swift_protobuf/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_grpc_grpc_swift",
        urls = ["https://github.com/grpc/grpc-swift/archive/2.0.0.tar.gz"],  # latest at time of writing
        sha256 = "f0264d6a90eef30d4189e5e8ccc39b429bcd0444c86b41d246c4b803c0676ecd",
        strip_prefix = "grpc-swift-2.0.0/",
        build_file = Label(
            "//third_party:com_github_grpc_grpc_swift/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_grpc_grpc_swift_nio_transport",
        urls = ["https://github.com/grpc/grpc-swift-nio-transport/archive/1.0.0.tar.gz"],  # latest at time of writing
        sha256 = "e590f7a30961802cbdf4f8cac37ae2dbc9ab2c8f8032c2ef2f66ed2b63623185",
        strip_prefix = "grpc-swift-nio-transport-1.0.0/",
        build_file = Label(
            "//third_party:com_github_grpc_grpc_swift_nio_transport/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_grpc_grpc_swift_protobuf",
        urls = ["https://github.com/grpc/grpc-swift-protobuf/archive/1.0.0.tar.gz"],  # latest at time of writing
        sha256 = "c31969782aa710e002f9a6214a9eb1e4292800e3606c2a092b034b97fdff52ac",
        strip_prefix = "grpc-swift-protobuf-1.0.0/",
        build_file = Label(
            "//third_party:com_github_grpc_grpc_swift_protobuf/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_docc_symbolkit",
        urls = ["https://github.com/apple/swift-docc-symbolkit/archive/refs/tags/swift-5.10-RELEASE.tar.gz"],
        sha256 = "de1d4b6940468ddb53b89df7aa1a81323b9712775b0e33e8254fa0f6f7469a97",
        strip_prefix = "swift-docc-symbolkit-swift-5.10-RELEASE",
        build_file = Label(
            "//third_party:com_github_apple_swift_docc_symbolkit/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio",
        urls = ["https://github.com/apple/swift-nio/archive/2.78.0.tar.gz"],  # pinned to grpc swift version
        sha256 = "7262fe6a134ce83fda666429ca88a511db517f36996955dafeb2068d66b7d260",
        strip_prefix = "swift-nio-2.78.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_http2",
        urls = ["https://github.com/apple/swift-nio-http2/archive/1.35.0.tar.gz"],  # pinned to grpc-swift version
        sha256 = "ffc425d7e2737d17b80a0227f2b2823eb95bd76cb681906494e5b795f64f6f5c",
        strip_prefix = "swift-nio-http2-1.35.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio_http2/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_transport_services",
        urls = ["https://github.com/apple/swift-nio-transport-services/archive/1.15.0.tar.gz"],  # pinned to grpc-swift version
        sha256 = "f3498dafa633751a52b9b7f741f7ac30c42bcbeb3b9edca6d447e0da8e693262",
        strip_prefix = "swift-nio-transport-services-1.15.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio_transport_services/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_extras",
        urls = ["https://github.com/apple/swift-nio-extras/archive/1.4.0.tar.gz"],  # pinned to grpc-swift version
        sha256 = "4684b52951d9d9937bb3e8ccd6b5daedd777021ef2519ea2f18c4c922843b52b",
        strip_prefix = "swift-nio-extras-1.4.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio_extras/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_log",
        urls = ["https://github.com/apple/swift-log/archive/1.4.4.tar.gz"],  # pinned to grpc-swift version
        sha256 = "48fe66426c784c0c20031f15dc17faf9f4c9037c192bfac2f643f65cb2321ba0",
        strip_prefix = "swift-log-1.4.4/",
        build_file = Label(
            "//third_party:com_github_apple_swift_log/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_ssl",
        urls = ["https://github.com/apple/swift-nio-ssl/archive/2.29.0.tar.gz"],  # pinned to grpc swift version
        sha256 = "f35a05309d791ec5ff23e1b0cdff2962872e2388fa0e27fced57566bb0383ea4",
        strip_prefix = "swift-nio-ssl-2.29.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio_ssl/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_collections",
        urls = ["https://github.com/apple/swift-collections/archive/1.1.3.tar.gz"],  # pinned to swift-nio @ grpc-swift version
        sha256 = "7e5e48d0dc2350bed5919be5cf60c485e72a30bd1f2baf718a619317677b91db",
        strip_prefix = "swift-collections-1.1.3/",
        build_file = Label(
            "//third_party:com_github_apple_swift_collections/BUILD.overlay",
        ),
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_atomics",
        urls = ["https://github.com/apple/swift-atomics/archive/1.1.0.tar.gz"],  # pinned to swift-nio @ grpc-swift version
        sha256 = "1bee7f469f7e8dc49f11cfa4da07182fbc79eab000ec2c17bfdce468c5d276fb",
        strip_prefix = "swift-atomics-1.1.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_atomics/BUILD.overlay",
        ),
    )

    # When using the "global index store" feature we rely on `index-import` to allow
    # using a global index.
    # TODO: we must depend on two versions of index-import to support backwards
    # compatibility between Xcode 16.3+ and older versions, we can remove the older
    # version once we drop support for Xcode 16.x.
    _maybe(
        http_archive,
        name = "build_bazel_rules_swift_index_import_5_8",
        build_file = Label("//third_party:build_bazel_rules_swift_index_import/BUILD.overlay"),
        canonical_id = "index-import-5.8",
        urls = ["https://github.com/MobileNativeFoundation/index-import/releases/download/5.8.0.1/index-import.tar.gz"],
        sha256 = "28c1ffa39d99e74ed70623899b207b41f79214c498c603915aef55972a851a15",
    )
    _maybe(
        http_archive,
        name = "build_bazel_rules_swift_index_import_6_1",
        build_file = Label("//third_party:build_bazel_rules_swift_index_import/BUILD.overlay"),
        canonical_id = "index-import-6.1",
        urls = ["https://github.com/MobileNativeFoundation/index-import/releases/download/6.1.0/index-import.tar.gz"],
        sha256 = "54d0477526bba0dc1560189dfc4f02d90aea536e9cb329e911f32b2a564b66f1",
    )

    _maybe(
        swift_autoconfiguration,
        name = "build_bazel_rules_swift_local_config",
    )

    if include_bzlmod_ready_dependencies:
        native.register_toolchains(
            # Use register_toolchain's target pattern expansion to register all toolchains in the package.
            "@build_bazel_rules_swift_local_config//:all",
        )

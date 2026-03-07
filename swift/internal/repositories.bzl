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

# buildifier: disable=unnamed-macro
def swift_rules_dependencies():
    """Fetches repositories that are dependencies of `rules_swift`.
    """

    http_archive(
        name = "com_github_apple_swift_protobuf",
        urls = ["https://github.com/apple/swift-protobuf/archive/1.20.2.tar.gz"],  # pinned to grpc-swift version
        sha256 = "3fb50bd4d293337f202d917b6ada22f9548a0a0aed9d9a4d791e6fbd8a246ebb",
        strip_prefix = "swift-protobuf-1.20.2/",
        build_file = Label(
            "//third_party:com_github_apple_swift_protobuf/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_grpc_grpc_swift",
        urls = ["https://github.com/grpc/grpc-swift/archive/1.16.0.tar.gz"],  # latest at time of writing
        sha256 = "58b60431d0064969f9679411264b82e40a217ae6bd34e17096d92cc4e47556a5",
        strip_prefix = "grpc-swift-1.16.0/",
        build_file = Label(
            "//third_party:com_github_grpc_grpc_swift/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_apple_swift_docc_symbolkit",
        urls = ["https://github.com/apple/swift-docc-symbolkit/archive/refs/tags/swift-5.10-RELEASE.tar.gz"],
        sha256 = "de1d4b6940468ddb53b89df7aa1a81323b9712775b0e33e8254fa0f6f7469a97",
        strip_prefix = "swift-docc-symbolkit-swift-5.10-RELEASE",
        build_file = Label(
            "//third_party:com_github_apple_swift_docc_symbolkit/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_apple_swift_nio",
        urls = ["https://github.com/apple/swift-nio/archive/2.51.0.tar.gz"],  # pinned to grpc swift version + version needed to fix linux build
        sha256 = "9ec79852fd03d2e933ece3299ea6c8b8de6960625f7246fd65958409d1420215",
        strip_prefix = "swift-nio-2.51.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_apple_swift_nio_http2",
        urls = ["https://github.com/apple/swift-nio-http2/archive/1.26.0.tar.gz"],  # pinned to grpc-swift version
        sha256 = "f0edfc9d6a7be1d587e5b403f2d04264bdfae59aac1d74f7d974a9022c6d2b25",
        strip_prefix = "swift-nio-http2-1.26.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio_http2/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_apple_swift_nio_transport_services",
        urls = ["https://github.com/apple/swift-nio-transport-services/archive/1.15.0.tar.gz"],  # pinned to grpc-swift version
        sha256 = "f3498dafa633751a52b9b7f741f7ac30c42bcbeb3b9edca6d447e0da8e693262",
        strip_prefix = "swift-nio-transport-services-1.15.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio_transport_services/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_apple_swift_nio_extras",
        urls = ["https://github.com/apple/swift-nio-extras/archive/1.4.0.tar.gz"],  # pinned to grpc-swift version
        sha256 = "4684b52951d9d9937bb3e8ccd6b5daedd777021ef2519ea2f18c4c922843b52b",
        strip_prefix = "swift-nio-extras-1.4.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio_extras/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_apple_swift_log",
        urls = ["https://github.com/apple/swift-log/archive/1.6.3.tar.gz"],  # pinned to version with linux build fix: https://github.com/apple/swift-log/pull/354
        sha256 = "5eaed6614cfaad882b8a0b5cb5d2177b533056b469ba431ad3f375193d370b70",
        strip_prefix = "swift-log-1.6.3/",
        build_file = Label(
            "//third_party:com_github_apple_swift_log/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_apple_swift_nio_ssl",
        urls = ["https://github.com/apple/swift-nio-ssl/archive/2.26.0.tar.gz"],  # pinned to version with linux build fix: https://github.com/apple/swift-nio-ssl/pull/448
        sha256 = "792882c884b2b89de0e9189557ea928bc019be2d9a89d63831876a746cbe9ce3",
        strip_prefix = "swift-nio-ssl-2.26.0/",
        build_file = Label(
            "//third_party:com_github_apple_swift_nio_ssl/BUILD.overlay",
        ),
    )

    http_archive(
        name = "com_github_apple_swift_collections",
        urls = ["https://github.com/apple/swift-collections/archive/1.0.4.tar.gz"],  # pinned to swift-nio @ grpc-swift version
        sha256 = "d9e4c8a91c60fb9c92a04caccbb10ded42f4cb47b26a212bc6b39cc390a4b096",
        strip_prefix = "swift-collections-1.0.4/",
        build_file = Label(
            "//third_party:com_github_apple_swift_collections/BUILD.overlay",
        ),
    )

    http_archive(
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
    http_archive(
        name = "build_bazel_rules_swift_index_import_5_8",
        build_file = Label("//third_party:build_bazel_rules_swift_index_import/BUILD.overlay"),
        canonical_id = "index-import-5.8",
        urls = ["https://github.com/MobileNativeFoundation/index-import/releases/download/5.8.0.1/index-import.tar.gz"],
        sha256 = "28c1ffa39d99e74ed70623899b207b41f79214c498c603915aef55972a851a15",
    )
    http_archive(
        name = "build_bazel_rules_swift_index_import_6_1",
        build_file = Label("//third_party:build_bazel_rules_swift_index_import/BUILD.overlay"),
        canonical_id = "index-import-6.1",
        urls = ["https://github.com/MobileNativeFoundation/index-import/releases/download/6.1.0.1/index-import.tar.gz"],
        sha256 = "9a54fc1674af6031125a9884480a1e31e1bcf48b8f558b3e8bcc6b6fcd6e8b61",
    )

    swift_autoconfiguration(name = "build_bazel_rules_swift_local_config")

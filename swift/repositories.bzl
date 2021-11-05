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

def swift_rules_dependencies():
    """Fetches repositories that are dependencies of `rules_swift`.

    Users should call this macro in their `WORKSPACE` to ensure that all of the
    dependencies of the Swift rules are downloaded and that they are isolated
    from changes to those dependencies.
    """
    _maybe(
        http_archive,
        name = "bazel_skylib",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
        ],
        sha256 = "1c531376ac7e5a180e0237938a2536de0c54d93f5c278634818e0efc952dd56c",
    )

    _maybe(
        http_archive,
        name = "build_bazel_apple_support",
        urls = [
            "https://github.com/bazelbuild/apple_support/releases/download/0.11.0/apple_support.0.11.0.tar.gz",
        ],
        sha256 = "76df040ade90836ff5543888d64616e7ba6c3a7b33b916aa3a4b68f342d1b447",
    )

    _maybe(
        http_archive,
        name = "rules_cc",
        # Latest 08-10-20
        urls = ["https://github.com/bazelbuild/rules_cc/archive/1477dbab59b401daa94acedbeaefe79bf9112167.tar.gz"],
        sha256 = "b87996d308549fc3933f57a786004ef65b44b83fd63f1b0303a4bbc3fd26bbaf",
        strip_prefix = "rules_cc-1477dbab59b401daa94acedbeaefe79bf9112167/",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_log",
        urls = ["https://github.com/apple/swift-log/archive/refs/tags/1.4.2.zip"],
        sha256 = "9fd608037153fa3944d212bb2082458343adf52bdc2b5060a319e197b77d6a82",
        strip_prefix = "swift-log-1.4.2/",
        type = "zip",
        build_file="@build_bazel_rules_swift//third_party:com_github_apple_swift_log/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio",
        urls = ["https://github.com/apple/swift-nio/archive/refs/tags/2.33.0.zip"],
        sha256 = "c9d586c0d53a49877214bd3a3c3c45986d5c1409c83dc7c6f135e47467f47963",
        strip_prefix = "swift-nio-2.33.0/",
        type = "zip",
        build_file="@build_bazel_rules_swift//third_party:com_github_apple_swift_nio/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_extras",
        urls = ["https://github.com/apple/swift-nio-extras/archive/refs/tags/1.10.2.zip"],
        sha256 = "7efb3e5b97b596b78561838770221146ac2dd5f33f92036cb11e8e35cb14d3ce",
        strip_prefix="swift-nio-extras-1.10.2/",
        type="zip",
        build_file="@build_bazel_rules_swift//third_party:com_github_apple_swift_nio_extras/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_http2",
        urls = ["https://github.com/apple/swift-nio-http2/archive/refs/tags/1.18.4.zip"],
        sha256 = "296447db362e6d3ad357b160c3b9f2e9ed96852039e8e5817dcc4012737cd72c",
        strip_prefix="swift-nio-http2-1.18.4/",
        type="zip",
        build_file="@build_bazel_rules_swift//third_party:com_github_apple_swift_nio_http2/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_ssl",
        urls = ["https://github.com/apple/swift-nio-ssl/archive/2.16.1.zip"],
        sha256 = "573b1c67429a85c32878b8d3979fa58987ac850dc11db76697d7b1bf44057843",
        strip_prefix = "swift-nio-ssl-2.16.1/",
        type = "zip",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_nio_ssl/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_nio_transport_services",
        urls = ["https://github.com/apple/swift-nio-transport-services/archive/1.11.3.zip"],
        sha256 = "1c9036131370a82f48577342aad700ee6afb955c99d513b3f1b626bc086d7e3d",
        strip_prefix = "swift-nio-transport-services-1.11.3/",
        type = "zip",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_nio_transport_services/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_apple_swift_protobuf",
        urls = ["https://github.com/apple/swift-protobuf/archive/1.12.0.zip"],
        sha256 = "a9c1c14d81df690ed4c15bfb3c0aab0cb7a3f198ee95620561b89b1da7b76a9f",
        strip_prefix = "swift-protobuf-1.12.0/",
        type = "zip",
        build_file = "@build_bazel_rules_swift//third_party:com_github_apple_swift_protobuf/BUILD.overlay",
    )

    _maybe(
        http_archive,
        name = "com_github_grpc_grpc_swift",
        urls = ["https://github.com/grpc/grpc-swift/archive/0.9.0.zip"],
        sha256 = "b9818134f497df073cb49e0df59bfeea801291230d6fc048fdc6aa76e453a3cb",
        strip_prefix = "grpc-swift-0.9.0/",
        type = "zip",
        build_file = "@build_bazel_rules_swift//third_party:com_github_grpc_grpc_swift/BUILD.overlay",
    )
    _maybe(
        http_archive,
        name = "com_github_grpc_grpc_swift_swiftnio",
        urls = ["https://github.com/grpc/grpc-swift/archive/1.5.0.zip"],
        sha256 = "573b12ca8f5c6848c503300df8d0a667d729d1457b925f5278f01497d90a9b30",
        strip_prefix = "grpc-swift-1.5.0/",
        type = "zip",
        build_file = "@build_bazel_rules_swift//third_party:com_github_grpc_grpc_swift_swiftnio/BUILD.overlay",
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
        name = "rules_proto",
        # latest as of 2021-01-27
        urls = [
            "https://github.com/bazelbuild/rules_proto/archive/a0761ed101b939e19d83b2da5f59034bffc19c12.zip",
        ],
        sha256 = "32c9deb114c9e2d6ea3afd48a4d203d775b60a01876186d1ad52d752a8be439f",
        strip_prefix = "rules_proto-a0761ed101b939e19d83b2da5f59034bffc19c12",
        type = "zip",
    )

    # It relies on `index-import` to import indexes into Bazel's remote
    # cache and allow using a global index internally in workers.
    # Note: this is only loaded if swift.index_while_building_v2 is enabled
    _maybe(
        http_archive,
        name = "build_bazel_rules_swift_index_import",
        build_file = "@build_bazel_rules_swift//third_party:build_bazel_rules_swift_index_import/BUILD.overlay",
        canonical_id = "index-import-5.3.2.6",
        urls = ["https://github.com/MobileNativeFoundation/index-import/releases/download/5.3.2.6/index-import.zip"],
        sha256 = "61a58363f56c5fd84d4ebebe0d9b5dd90c74ae170405a7b9018e8cf698e679de",
    )

    _maybe(
        swift_autoconfiguration,
        name = "build_bazel_rules_swift_local_config",
    )

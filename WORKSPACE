workspace(name = "build_bazel_rules_swift")

load(
    "//swift:repositories.bzl",
    "swift_rules_dependencies",
)

swift_rules_dependencies()

load(
    "//swift:extras.bzl",
    "swift_rules_extra_dependencies",
)

swift_rules_extra_dependencies()

load("@rules_cc//cc:extensions.bzl", "compatibility_proxy_repo")

compatibility_proxy_repo()

load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")

bazel_skylib_workspace()

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "SwiftSyntax",
    sha256 = "527a5c6d19987acbb5019efa067b0fbd127e06187a0689c3f1098fd22c1a7d43",
    strip_prefix = "swift-syntax-01fc3e3ed4d26121c06790abf8fe5ddaa22a4cc5",
    url = "https://github.com/apple/swift-syntax/archive/01fc3e3ed4d26121c06790abf8fe5ddaa22a4cc5.tar.gz",
)

load("@rules_shell//shell:repositories.bzl", "rules_shell_dependencies", "rules_shell_toolchains")

rules_shell_dependencies()

rules_shell_toolchains()

load("@com_google_protobuf//:protobuf_deps.bzl", "protobuf_deps")

protobuf_deps()

load("@rules_java//java:rules_java_deps.bzl", "rules_java_dependencies")

rules_java_dependencies()

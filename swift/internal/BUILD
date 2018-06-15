package(default_visibility = ["//:__subpackages__"])

licenses(["notice"])

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]) + [
        # We should be depending on a filegroup here that represents this file
        # and its dependencies, but it doesn't exist yet.
        "@bazel_tools//tools/cpp:toolchain_utils.bzl",
    ],
    visibility = [
        "@build_bazel_rules_swift//swift:__pkg__",
    ],
)

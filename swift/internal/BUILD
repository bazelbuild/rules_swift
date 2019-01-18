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
        "@bazel_tools//tools/build_defs/cc:action_names_test_files",
    ],
    visibility = [
        "//swift:__pkg__",
    ],
)

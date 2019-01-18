package(default_visibility = ["//visibility:public"])

licenses(["notice"])

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]) + [
        "//tools/mkdir_and_run:for_bazel_tests",
        "//tools/wrappers:for_bazel_tests",
    ],
    visibility = [
        "//:__pkg__",
    ],
)

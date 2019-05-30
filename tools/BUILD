package(default_visibility = ["//visibility:public"])

licenses(["notice"])

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]) + [
        "//tools/common:for_bazel_tests",
        "//tools/mkdir_and_run:for_bazel_tests",
        "//tools/worker:for_bazel_tests",
    ],
    visibility = [
        "//:__pkg__",
    ],
)

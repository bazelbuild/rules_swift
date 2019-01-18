package(default_visibility = ["//visibility:public"])

licenses(["notice"])

exports_files([
    "swift.bzl",
])

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]) + [
        "//swift/internal:for_bazel_tests",
    ],
    visibility = [
        "//:__pkg__",
    ],
)

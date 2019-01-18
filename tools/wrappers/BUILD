licenses(["notice"])

sh_binary(
    name = "bazel_xcode_wrapper",
    srcs = ["bazel_xcode_wrapper.sh"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "swift_wrapper",
    srcs = ["swift_wrapper.sh"],
    visibility = ["//visibility:public"],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]),
    visibility = [
        "//tools:__pkg__",
    ],
)

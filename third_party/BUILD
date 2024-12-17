# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = True,
    srcs = glob(["**"]) + [
        "//third_party/bazel_protos:for_bazel_tests",
    ],
    visibility = [
        "//:__pkg__",
    ],
)

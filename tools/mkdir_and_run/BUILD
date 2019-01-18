licenses(["notice"])

sh_binary(
    name = "mkdir_and_run",
    srcs = ["mkdir_and_run.sh"],
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

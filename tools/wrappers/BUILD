licenses(["notice"])

sh_binary(
    name = "xcrunwrapper",
    srcs = ["xcrunwrapper.sh"],
    visibility = ["//visibility:public"],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]),
    visibility = [
        "@build_bazel_rules_swift//tools:__pkg__",
    ],
)

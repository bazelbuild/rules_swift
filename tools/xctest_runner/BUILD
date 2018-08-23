licenses(["notice"])

filegroup(
    name = "xctest_runner_template",
    srcs = ["xctest_runner.sh.template"],
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

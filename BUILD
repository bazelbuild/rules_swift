package(default_visibility = ["//visibility:public"])

licenses(["notice"])

exports_files(["LICENSE"])

# Consumed by Bazel integration tests (such as those defined in rules_apple).
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = [
        "@build_bazel_rules_swift//swift:for_bazel_tests",
        "@build_bazel_rules_swift//tools:for_bazel_tests",
    ],
)

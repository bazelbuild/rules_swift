package(default_visibility = ["//:__subpackages__"])

licenses(["notice"])

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]),
    visibility = [
        "@build_bazel_rules_swift//swift:__pkg__",
    ],
)

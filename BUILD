package(default_visibility = ["//visibility:public"])

licenses(["notice"])

exports_files(["LICENSE"])

# Consumed by Bazel integration tests (such as those defined in rules_apple).
filegroup(
    name = "for_bazel_tests",
    testonly = True,
    srcs = [
        "WORKSPACE",
        "//swift:for_bazel_tests",
        "//third_party:for_bazel_tests",
        "//tools:for_bazel_tests",
    ],
)

platform(
    name = "windows",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:windows",
        "@bazel_tools//tools/cpp:clang-cl",
    ],
)

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

load("@bazel_skylib//rules:common_settings.bzl", "bool_setting")

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

# Configuration setting for enabling the generation of swiftinterface files.
bool_setting(
    name = "emit_swiftinterface",
    build_setting_default = False,
)

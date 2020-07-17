load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:common_settings.bzl", "bool_setting")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

bzl_library(
    name = "swift",
    srcs = ["swift.bzl"],
    deps = [
        "//swift/internal:build_defs",
        "//swift/internal:rules",
        "//swift/internal:swift_common",
    ],
)

bzl_library(
    name = "stats",
    srcs = ["stats.bzl"],
    deps = [
        "//swift/internal:build_defs",
    ],
)

bzl_library(
    name = "repositories",
    srcs = ["repositories.bzl"],
    deps = [
        "//swift/internal:toolchain_support",
    ],
)

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

# Allows a user to override the default Swift driver during a build, if the
# toolchain is using the default.
label_flag(
    name = "default_swift_executable",
    build_setting_default = ":empty",
)

# Empty filegroup used as the default value for `:default_swift_executable`
# since the `build_setting_default` value is required.
filegroup(
    name = "empty",
    visibility = ["//visibility:private"],
)

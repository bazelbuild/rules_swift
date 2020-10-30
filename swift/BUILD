load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:common_settings.bzl", "bool_setting")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

bzl_library(
    name = "repositories",
    srcs = ["repositories.bzl"],
    deps = [
        "//swift/internal:swift_autoconfiguration",
        "@bazel_tools//tools/build_defs/repo:http.bzl",
    ],
)

bzl_library(
    name = "stats",
    srcs = ["stats.bzl"],
    deps = ["//swift/internal:utils"],
)

bzl_library(
    name = "swift",
    srcs = ["swift.bzl"],
    deps = [
        "//swift/internal:providers",
        "//swift/internal:swift_binary_test",
        "//swift/internal:swift_c_module",
        "//swift/internal:swift_common",
        "//swift/internal:swift_grpc_library",
        "//swift/internal:swift_import",
        "//swift/internal:swift_library",
        "//swift/internal:swift_module_alias",
        "//swift/internal:swift_proto_library",
        "//swift/internal:swift_usage_aspect",
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

# Configuration setting for forcing generation of Apple targets.
# NOTE: this is only intended for use with transitions that want to force
# building of an Apple target when building for Linux.
bool_setting(
    name = "force_apple_target",
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

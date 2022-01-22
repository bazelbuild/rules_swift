load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag", "bool_setting")
load(
    "//swift/internal:build_settings.bzl",
    "per_module_swiftcopt_flag",
)

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

bzl_library(
    name = "bazel_tools_bzl",
    srcs = ["@bazel_tools//tools:bzl_srcs"],
)

bzl_library(
    name = "repositories",
    srcs = ["repositories.bzl"],
    deps = [
        ":bazel_tools_bzl",
        "//swift/internal:swift_autoconfiguration",
    ],
)

bzl_library(
    name = "swift",
    srcs = ["swift.bzl"],
    deps = [
        "//swift/internal:providers",
        "//swift/internal:swift_binary_test",
        "//swift/internal:swift_c_module",
        "//swift/internal:swift_common",
        "//swift/internal:swift_feature_allowlist",
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

# User settable flag that specifies additional Swift copts on a per-swiftmodule basis.
per_module_swiftcopt_flag(
    name = "per_module_swiftcopt",
    build_setting_default = "",
    visibility = ["//visibility:public"],
)

# Configuration setting for enabling the generation of swiftinterface files.
bool_setting(
    name = "emit_swiftinterface",
    build_setting_default = False,
)

bool_flag(
    name = "universal_tools",
    build_setting_default = False,
)

config_setting(
    name = "universal_tools_config",
    flag_values = {
        "@build_bazel_rules_swift//swift:universal_tools": "true",
    },
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

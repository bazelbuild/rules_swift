load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:common_settings.bzl", "bool_setting")
load(
    "//swift/internal:build_settings.bzl",
    "per_module_swiftcopt_flag",
)
load(":swift.bzl", "swift_interop_hint")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

bzl_library(
    name = "swift",
    srcs = ["swift.bzl"],
    deps = [
        "//swift/internal:providers",
        "//swift/internal:swift_binary",
        "//swift/internal:swift_clang_module_aspect",
        "//swift/internal:swift_common",
        "//swift/internal:swift_extract_symbol_graph",
        "//swift/internal:swift_feature_allowlist",
        "//swift/internal:swift_grpc_library",
        "//swift/internal:swift_import",
        "//swift/internal:swift_interop_hint",
        "//swift/internal:swift_library",
        "//swift/internal:swift_module_alias",
        "//swift/internal:swift_package_configuration",
        "//swift/internal:swift_proto_library",
        "//swift/internal:swift_symbol_graph_aspect",
        "//swift/internal:swift_test",
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

# An aspect hint that enables module map generation for a non-Swift,
# non-Objective-C target, deriving the module name automatically based on the
# hinted target's label.
swift_interop_hint(
    name = "auto_module",
    visibility = ["//visibility:public"],
)

# An aspect hint that suppresses generation of a module for a non-Swift target
# that would otherwise generate one by default, like an `objc_library`.
swift_interop_hint(
    name = "no_module",
    suppressed = True,
    visibility = ["//visibility:public"],
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

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag", "bool_setting")
load(
    "//swift/internal:build_settings.bzl",
    "per_module_swiftcopt_flag",
    "repeatable_string_flag",
)

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

bzl_library(
    name = "repositories",
    srcs = ["repositories.bzl"],
    deps = [
        "//doc:bazel_tools_bzl",
        "//swift/internal:swift_autoconfiguration",
    ],
)

bzl_library(
    name = "module_name",
    srcs = ["module_name.bzl"],
    deps = [
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "swift_compiler_plugin",
    srcs = ["swift_compiler_plugin.bzl"],
    deps = [
        ":module_name",
        "//swift/internal:compiling",
        "//swift/internal:linking",
        "//swift/internal:providers",
        "//swift/internal:swift_common",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
        "@build_bazel_apple_support//lib:apple_support",
        "@build_bazel_apple_support//lib:lipo",
        "@build_bazel_apple_support//lib:transitions",
    ],
)

bzl_library(
    name = "swift",
    srcs = ["swift.bzl"],
    deps = [
        ":swift_compiler_plugin",
        "//swift/deprecated_proto:deprecated_swift_grpc_library",
        "//swift/deprecated_proto:deprecated_swift_proto_library",
        "//swift/internal:providers",
        "//swift/internal:swift_binary_test_rules",
        "//swift/internal:swift_c_module",
        "//swift/internal:swift_common",
        "//swift/internal:swift_feature_allowlist",
        "//swift/internal:swift_import",
        "//swift/internal:swift_library",
        "//swift/internal:swift_library_group",
        "//swift/internal:swift_module_alias",
        "//swift/internal:swift_package_configuration",
        "//swift/internal:swift_usage_aspect",
    ],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]) + [
        "//swift/internal:for_bazel_tests",
        "//swift/toolchains:for_bazel_tests",
    ],
    visibility = [
        "//:__pkg__",
    ],
)

# Additional Swift compiler flags that will be applied to all `SwiftCompile`
# actions in non-execution configurations (but not module interface compile
# actions or Clang module compile actions).
repeatable_string_flag(
    name = "copt",
    build_setting_default = [],
    visibility = ["//visibility:public"],
)

# Additional Swift compiler flags that will be applied to all `SwiftCompile`
# actions in execution configurations (but not module interface compile
# actions or Clang module compile actions).
repeatable_string_flag(
    name = "exec_copt",
    build_setting_default = [],
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

# Configuration setting for enabling the generation of private swiftinterface files (e.g. those for `@_spi`).
bool_setting(
    name = "emit_private_swiftinterface",
    build_setting_default = False,
)

# NOTE: Enabling this flag will transition --proto_compiler to
# //tools/protoc_wrapper:protoc for swift_grpc_library and swift_proto_library,
# unless you set --proto_compiler manually.
# If you use this flag, we recommend to also set
# --proto_compiler=@build_bazel_rules_swift//tools/protoc_wrapper:protoc to
# ensure that the same proto compiler is used across your builds.
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

bzl_library(
    name = "extensions",
    srcs = ["extensions.bzl"],
    deps = [":repositories"],
)

bzl_library(
    name = "extras",
    srcs = ["extras.bzl"],
    deps = [
        "@build_bazel_apple_support//lib:repositories",
        "@rules_proto//proto:repositories",
    ],
)

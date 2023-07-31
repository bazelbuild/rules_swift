load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load(
    "@bazel_skylib//rules:common_settings.bzl",
    "bool_setting",
    "string_flag",
)
load(
    "//swift/internal:build_settings.bzl",
    "per_module_swiftcopt_flag",
)
load(":swift_interop_hint.bzl", "swift_interop_hint")
load(":swift_module_mapping.bzl", "swift_module_mapping")

package(
    default_visibility = ["//visibility:public"],
)

licenses(["notice"])

bzl_library(
    name = "module_name",
    srcs = ["module_name.bzl"],
    deps = [
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "providers",
    srcs = ["providers.bzl"],
)

bzl_library(
    name = "swift_binary",
    srcs = ["swift_binary.bzl"],
    deps = [
        ":module_name",
        ":providers",
        "//swift/internal:compiling",
        "//swift/internal:linking",
        "//swift/internal:output_groups",
        "//swift/internal:providers",
        "//swift/internal:toolchain_utils",
        "//swift/internal:transitions",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_clang_module_aspect",
    srcs = ["swift_clang_module_aspect.bzl"],
    deps = [
        ":module_name",
        ":providers",
        "//swift/internal:attrs",
        "//swift/internal:compiling",
        "//swift/internal:feature_names",
        "//swift/internal:features",
        "//swift/internal:module_maps",
        "//swift/internal:swift_interop_info",
        "//swift/internal:toolchain_utils",
        "//swift/internal:utils",
        "@bazel_skylib//lib:sets",
    ],
)

bzl_library(
    name = "swift_common",
    srcs = ["swift_common.bzl"],
    deps = [
        "//swift/internal:attrs",
        "//swift/internal:compiling",
        "//swift/internal:features",
        "//swift/internal:linking",
        "//swift/internal:symbol_graph_extracting",
        "//swift/internal:toolchain_utils",
        "//swift/internal:transitions",
    ],
)

bzl_library(
    name = "swift_compiler_plugin",
    srcs = ["swift_compiler_plugin.bzl"],
    deps = [
        ":module_name",
        ":providers",
        "//swift/internal:compiling",
        "//swift/internal:linking",
        "//swift/internal:output_groups",
        "//swift/internal:providers",
        "//swift/internal:toolchain_utils",
        "//swift/internal:transitions",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_cross_import_overlay",
    srcs = ["swift_cross_import_overlay.bzl"],
    deps = [
        ":providers",
        "//swift/internal:providers",
    ],
)

bzl_library(
    name = "swift_extract_symbol_graph",
    srcs = ["swift_extract_symbol_graph.bzl"],
    deps = [
        ":providers",
        ":swift_symbol_graph_aspect",
    ],
)

bzl_library(
    name = "swift_feature_allowlist",
    srcs = ["swift_feature_allowlist.bzl"],
    deps = [
        ":providers",
        "//swift/internal:package_specs",
    ],
)

bzl_library(
    name = "swift_grpc_library",
    srcs = ["swift_grpc_library.bzl"],
    deps = [
        ":module_name",
        ":providers",
        "//swift/internal:attrs",
        "//swift/internal:compiling",
        "//swift/internal:feature_names",
        "//swift/internal:features",
        "//swift/internal:linking",
        "//swift/internal:output_groups",
        "//swift/internal:proto_gen_utils",
        "//swift/internal:toolchain_utils",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_import",
    srcs = ["swift_import.bzl"],
    deps = [
        ":providers",
        "//swift/internal:attrs",
        "//swift/internal:compiling",
        "//swift/internal:features",
        "//swift/internal:linking",
        "//swift/internal:toolchain_utils",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_interop_hint",
    srcs = ["swift_interop_hint.bzl"],
    deps = [
        ":swift_interop_info",
    ],
)

bzl_library(
    name = "swift_interop_info",
    srcs = ["swift_interop_info.bzl"],
    deps = [
        "//swift/internal:swift_interop_info",
    ],
)

bzl_library(
    name = "swift_library",
    srcs = ["swift_library.bzl"],
    deps = [
        ":module_name",
        ":providers",
        ":swift_clang_module_aspect",
        "//swift/internal:attrs",
        "//swift/internal:build_settings",
        "//swift/internal:compiling",
        "//swift/internal:feature_names",
        "//swift/internal:features",
        "//swift/internal:linking",
        "//swift/internal:output_groups",
        "//swift/internal:providers",
        "//swift/internal:toolchain_utils",
        "//swift/internal:transitions",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:sets",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "swift_module_mapping",
    srcs = ["swift_module_mapping.bzl"],
    deps = [
        "//swift/internal:providers",
    ],
)

bzl_library(
    name = "swift_module_mapping_test",
    srcs = ["swift_module_mapping_test.bzl"],
    deps = [
        ":providers",
        "//swift/internal:providers",
    ],
)

bzl_library(
    name = "swift_package_configuration",
    srcs = ["swift_package_configuration.bzl"],
    deps = [
        ":providers",
        "//swift/internal:package_specs",
    ],
)

bzl_library(
    name = "swift_proto_library",
    srcs = ["swift_proto_library.bzl"],
    deps = [
        ":providers",
        "//swift/internal:swift_protoc_gen_aspect",
    ],
)

bzl_library(
    name = "swift_symbol_graph_aspect",
    srcs = ["swift_symbol_graph_aspect.bzl"],
    deps = [
        "//swift/internal:swift_symbol_graph_aspect",
    ],
)

bzl_library(
    name = "swift_test",
    srcs = ["swift_test.bzl"],
    deps = [
        ":module_name",
        ":providers",
        "//swift/internal:compiling",
        "//swift/internal:linking",
        "//swift/internal:output_groups",
        "//swift/internal:providers",
        "//swift/internal:swift_symbol_graph_aspect",
        "//swift/internal:symbol_graph_extracting",
        "//swift/internal:toolchain_utils",
        "//swift/internal:transitions",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
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
    visibility = ["//visibility:public"],
)

# Allows a user to override the default Swift driver during a build, if the
# toolchain is using the default.
label_flag(
    name = "default_swift_executable",
    build_setting_default = ":empty",
    visibility = ["//visibility:public"],
)

# Empty filegroup used as the default value for `:default_swift_executable`
# since the `build_setting_default` value is required.
filegroup(
    name = "empty",
    visibility = ["//visibility:private"],
)

# Provides the mapping that will be passed to the compiler as module aliases.
label_flag(
    name = "module_mapping",
    build_setting_default = ":empty_module_mapping",
    visibility = ["//visibility:public"],
)

# The default empty module mapping used when the `:module_mapping` flag is not
# set.
swift_module_mapping(
    name = "empty_module_mapping",
    aliases = {},
    visibility = ["//visibility:private"],
)

# The value to pass to the Swift compiler for the `-cxx-interoperability-mode=`
# flag. Most users should never need to set this flag directly; it is applied by
# a transition from top-level rules like `swift_binary` to enable C++ interop
# for their entire build graph. However, it may still be useful to manually set
# when testing, as it would be the only way to `bazel build` a standalone
# `swift_library` in the correct mode.
string_flag(
    name = "cxx_interop",
    build_setting_default = "",
    visibility = ["//visibility:public"],
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

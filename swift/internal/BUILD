load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

licenses(["notice"])

bzl_library(
    name = "rules",
    srcs = [
        "swift_binary_test.bzl",
        "swift_c_module.bzl",
        "swift_grpc_library.bzl",
        "swift_import.bzl",
        "swift_library.bzl",
        "swift_module_alias.bzl",
        "swift_proto_library.bzl",
        "swift_protoc_gen_aspect.bzl",
    ],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":build_defs",
        ":swift_common",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:new_sets",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "swift_common",
    srcs = ["swift_common.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [":build_defs"],
)

bzl_library(
    name = "build_defs",
    srcs = [
        "actions.bzl",
        "attrs.bzl",
        "autolinking.bzl",
        "compiling.bzl",
        "debugging.bzl",
        "derived_files.bzl",
        "feature_names.bzl",
        "features.bzl",
        "linking.bzl",
        "module_maps.bzl",
        "proto_gen_utils.bzl",
        "providers.bzl",
        "swift_clang_module_aspect.bzl",
        "swift_usage_aspect.bzl",
        "toolchain_config.bzl",
        "utils.bzl",
        "vfsoverlay.bzl",
    ],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:new_sets",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//lib:sets",
        "@bazel_skylib//lib:types",
        "@bazel_skylib//rules:common_settings",
        "@bazel_tools//tools/build_defs/cc:action_names.bzl",
    ],
)

bzl_library(
    name = "toolchain_support",
    srcs = [
        "swift_autoconfiguration.bzl",
        "swift_toolchain.bzl",
        "xcode_swift_toolchain.bzl",
    ],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":build_defs",
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:paths",
    ],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]) + [
        # We should be depending on a filegroup here that represents this file
        # and its dependencies, but it doesn't exist yet.
        "@bazel_tools//tools/cpp:toolchain_utils.bzl",
        "@bazel_tools//tools/build_defs/cc:action_names_test_files",
    ],
    visibility = [
        "//swift:__pkg__",
    ],
)

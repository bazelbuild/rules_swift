load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

licenses(["notice"])

bzl_library(
    name = "actions",
    srcs = ["actions.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":features",
        ":toolchain_config",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "attrs",
    srcs = ["attrs.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":providers",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "autolinking",
    srcs = ["autolinking.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":actions",
        ":toolchain_config",
    ],
)

bzl_library(
    name = "compiling",
    srcs = ["compiling.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":actions",
        ":autolinking",
        ":debugging",
        ":derived_files",
        ":feature_names",
        ":features",
        ":providers",
        ":toolchain_config",
        ":utils",
        ":vfsoverlay",
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "debugging",
    srcs = ["debugging.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":actions",
        ":derived_files",
        ":toolchain_config",
    ],
)

bzl_library(
    name = "derived_files",
    srcs = ["derived_files.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":utils",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "features",
    srcs = ["features.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":feature_names",
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:new_sets",
    ],
)

bzl_library(
    name = "linking",
    srcs = ["linking.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":derived_files",
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:partial",
        "@bazel_tools//tools/build_defs/cc:action_names.bzl",
    ],
)

bzl_library(
    name = "module_maps",
    srcs = ["module_maps.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = ["@bazel_skylib//lib:paths"],
)

bzl_library(
    name = "proto_gen_utils",
    srcs = ["proto_gen_utils.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":utils",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "providers",
    srcs = ["providers.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        "@bazel_skylib//lib:sets",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "swift_autoconfiguration",
    srcs = ["swift_autoconfiguration.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = ["@build_bazel_rules_swift//swift/internal:feature_names"],
)

bzl_library(
    name = "swift_c_module",
    srcs = ["swift_c_module.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":swift_common",
        ":utils",
    ],
)

bzl_library(
    name = "swift_feature_allowlist",
    srcs = ["swift_feature_allowlist.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":providers",
    ],
)

bzl_library(
    name = "swift_binary_test",
    srcs = ["swift_binary_test.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":compiling",
        ":derived_files",
        ":feature_names",
        ":linking",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:partial",
    ],
)

bzl_library(
    name = "swift_clang_module_aspect",
    srcs = ["swift_clang_module_aspect.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":attrs",
        ":compiling",
        ":derived_files",
        ":feature_names",
        ":features",
        ":module_maps",
        ":providers",
        ":utils",
    ],
)

bzl_library(
    name = "swift_common",
    srcs = ["swift_common.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":attrs",
        ":compiling",
        ":features",
        ":linking",
        ":providers",
        ":swift_clang_module_aspect",
    ],
)

bzl_library(
    name = "swift_grpc_library",
    srcs = ["swift_grpc_library.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":compiling",
        ":feature_names",
        ":linking",
        ":proto_gen_utils",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
        "@rules_proto//proto:defs",
    ],
)

bzl_library(
    name = "swift_import",
    srcs = ["swift_import.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":attrs",
        ":compiling",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_library",
    srcs = ["swift_library.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":attrs",
        ":build_settings",
        ":compiling",
        ":feature_names",
        ":linking",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:sets",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "swift_module_alias",
    srcs = ["swift_module_alias.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":compiling",
        ":derived_files",
        ":linking",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_proto_library",
    srcs = ["swift_proto_library.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":providers",
        ":swift_protoc_gen_aspect",
        "@rules_proto//proto:defs",
    ],
)

bzl_library(
    name = "swift_protoc_gen_aspect",
    srcs = ["swift_protoc_gen_aspect.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":attrs",
        ":compiling",
        ":feature_names",
        ":linking",
        ":proto_gen_utils",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//rules:common_settings",
        "@rules_proto//proto:defs",
    ],
)

bzl_library(
    name = "swift_toolchain",
    srcs = ["swift_toolchain.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":actions",
        ":attrs",
        ":autolinking",
        ":compiling",
        ":debugging",
        ":feature_names",
        ":features",
        ":providers",
        ":toolchain_config",
        ":utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:partial",
        "@bazel_tools//tools/cpp:toolchain_utils.bzl",
    ],
)

bzl_library(
    name = "swift_usage_aspect",
    srcs = ["swift_usage_aspect.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [":providers"],
)

bzl_library(
    name = "toolchain_config",
    srcs = ["toolchain_config.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "utils",
    srcs = ["utils.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = ["@bazel_skylib//lib:paths"],
)

bzl_library(
    name = "xcode_swift_toolchain",
    srcs = ["xcode_swift_toolchain.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":actions",
        ":attrs",
        ":compiling",
        ":feature_names",
        ":features",
        ":providers",
        ":toolchain_config",
        ":utils",
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//rules:common_settings",
        "@bazel_tools//tools/cpp:toolchain_utils.bzl",
    ],
)

bzl_library(
    name = "feature_names",
    srcs = ["feature_names.bzl"],
    visibility = ["//swift:__subpackages__"],
)

bzl_library(
    name = "vfsoverlay",
    srcs = ["vfsoverlay.bzl"],
    visibility = ["//swift:__subpackages__"],
)

bzl_library(
    name = "build_settings",
    srcs = ["build_settings.bzl"],
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

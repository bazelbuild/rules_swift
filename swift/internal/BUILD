load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@rules_proto//proto:defs.bzl", "proto_lang_toolchain")

licenses(["notice"])

package(
    default_visibility = [
        "//swift:__subpackages__",
    ],
)

proto_lang_toolchain(
    name = "proto_swift_toolchain",
    command_line = "--swift_out=$(OUT)",
    mnemonic = "ProtocGenSwift",
    output_files = "multiple",
    plugin = "@com_github_apple_swift_protobuf//:ProtoCompilerPlugin",
    plugin_format_flag = "--plugin=protoc-gen-swift=%s",
    progress_message = "Generating Swift sources for %{label}",
    runtime = "@com_github_apple_swift_protobuf//:SwiftProtobuf",
    visibility = ["//visibility:public"],
)

bzl_library(
    name = "action_names",
    srcs = ["action_names.bzl"],
)

bzl_library(
    name = "actions",
    srcs = ["actions.bzl"],
    deps = [
        ":features",
        "//swift/toolchains/config:action_config",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "attrs",
    srcs = ["attrs.bzl"],
    deps = [
        ":providers",
        "//swift:providers",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "build_settings",
    srcs = ["build_settings.bzl"],
)

bzl_library(
    name = "compiling",
    srcs = ["compiling.bzl"],
    deps = [
        ":action_names",
        ":actions",
        ":explicit_module_map_file",
        ":feature_names",
        ":features",
        ":module_maps",
        ":utils",
        ":wmo",
        "//swift:providers",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//lib:sets",
    ],
)

bzl_library(
    name = "debugging",
    srcs = ["debugging.bzl"],
    deps = [
        ":action_names",
        ":actions",
        ":feature_names",
        ":features",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "explicit_module_map_file",
    srcs = ["explicit_module_map_file.bzl"],
)

bzl_library(
    name = "feature_names",
    srcs = ["feature_names.bzl"],
)

bzl_library(
    name = "features",
    srcs = ["features.bzl"],
    deps = [
        ":feature_names",
        ":package_specs",
        ":target_triples",
        "@bazel_skylib//lib:new_sets",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "linking",
    srcs = ["linking.bzl"],
    deps = [
        ":attrs",
        ":debugging",
        ":feature_names",
        ":features",
        "//swift:swift_clang_module_aspect",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "module_maps",
    srcs = ["module_maps.bzl"],
    deps = ["@bazel_skylib//lib:sets"],
)

bzl_library(
    name = "package_specs",
    srcs = ["package_specs.bzl"],
)

bzl_library(
    name = "proto_gen_utils",
    srcs = ["proto_gen_utils.bzl"],
    deps = ["@bazel_skylib//lib:paths"],
)

bzl_library(
    name = "providers",
    srcs = ["providers.bzl"],
    visibility = [
        "//swift:__subpackages__",
    ],
)

bzl_library(
    name = "swift_interop_info",
    srcs = ["swift_interop_info.bzl"],
)

bzl_library(
    name = "swift_protoc_gen_aspect",
    srcs = ["swift_protoc_gen_aspect.bzl"],
    deps = [
        ":attrs",
        ":compiling",
        ":feature_names",
        ":features",
        ":linking",
        ":proto_gen_utils",
        ":toolchain_utils",
        ":utils",
        "//swift:module_name",
        "//swift:providers",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "swift_symbol_graph_aspect",
    srcs = ["swift_symbol_graph_aspect.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":attrs",
        ":features",
        ":symbol_graph_extracting",
        ":toolchain_utils",
        "//swift:providers",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "symbol_graph_extracting",
    srcs = ["symbol_graph_extracting.bzl"],
    deps = [
        ":action_names",
        ":actions",
        ":utils",
        "//swift:providers",
    ],
)

bzl_library(
    name = "target_triples",
    srcs = ["target_triples.bzl"],
)

bzl_library(
    name = "toolchain_utils",
    srcs = ["toolchain_utils.bzl"],
)

bzl_library(
    name = "transitions",
    srcs = ["transitions.bzl"],
)

bzl_library(
    name = "utils",
    srcs = ["utils.bzl"],
    deps = [
        "//swift:providers",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "wmo",
    srcs = ["wmo.bzl"],
    deps = [
        ":feature_names",
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

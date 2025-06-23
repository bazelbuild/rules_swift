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
    denylisted_protos = [
        # keep sorted
        "@com_google_protobuf//:any_proto",
        "@com_google_protobuf//:api_proto",
        "@com_google_protobuf//:descriptor_proto",
        "@com_google_protobuf//:duration_proto",
        "@com_google_protobuf//:empty_proto",
        "@com_google_protobuf//:field_mask_proto",
        "@com_google_protobuf//:source_context_proto",
        "@com_google_protobuf//:struct_proto",
        "@com_google_protobuf//:timestamp_proto",
        "@com_google_protobuf//:type_proto",
        "@com_google_protobuf//:wrappers_proto",
    ],
    mnemonic = "ProtocGenSwift",
    output_files = "multiple",
    plugin = "@com_github_apple_swift_protobuf//:protoc-gen-swift",
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
    name = "binary_attrs",
    srcs = ["binary_attrs.bzl"],
    deps = [
        ":attrs",
        "//swift:swift_clang_module_aspect",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "build_settings",
    srcs = ["build_settings.bzl"],
    deps = ["@bazel_skylib//rules:common_settings"],
)

bzl_library(
    name = "compiling",
    srcs = ["compiling.bzl"],
    deps = [
        ":action_names",
        ":actions",
        ":attrs",
        ":explicit_module_map_file",
        ":feature_names",
        ":features",
        ":module_maps",
        ":optimization",
        ":toolchain_utils",
        ":utils",
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
        "@bazel_skylib//lib:new_sets",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "interface_synthesizing",
    srcs = ["interface_synthesizing.bzl"],
    deps = [
        ":action_names",
        ":actions",
        ":features",
        ":toolchain_utils",
        ":utils",
        "//swift:providers",
    ],
)

bzl_library(
    name = "linking",
    srcs = ["linking.bzl"],
    deps = [
        ":debugging",
        ":features",
        ":toolchain_utils",
        ":utils",
        "//swift:providers",
    ],
)

bzl_library(
    name = "module_maps",
    srcs = ["module_maps.bzl"],
    deps = ["@bazel_skylib//lib:sets"],
)

bzl_library(
    name = "optimization",
    srcs = ["optimization.bzl"],
    deps = [
        ":feature_names",
    ],
)

bzl_library(
    name = "output_groups",
    srcs = ["output_groups.bzl"],
)

bzl_library(
    name = "package_specs",
    srcs = ["package_specs.bzl"],
)

bzl_library(
    name = "proto_gen_utils",
    srcs = ["proto_gen_utils.bzl"],
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
        ":output_groups",
        ":proto_gen_utils",
        ":toolchain_utils",
        ":utils",
        "//swift:module_name",
        "//swift:providers",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_symbol_graph_aspect",
    srcs = ["swift_symbol_graph_aspect.bzl"],
    visibility = [
        "//devtools/swift/semantic_analysis/aspect/versioned:__pkg__",
        "//swift:__pkg__",
    ],
    deps = [
        ":features",
        ":symbol_graph_extracting",
        ":toolchain_utils",
        "//swift:providers",
        "//swift:swift_clang_module_aspect",
    ],
)

bzl_library(
    name = "symbol_graph_extracting",
    srcs = ["symbol_graph_extracting.bzl"],
    deps = [
        ":action_names",
        ":actions",
        ":features",
        ":toolchain_utils",
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
    deps = ["@rules_cc//cc:find_cc_toolchain_bzl"],
)

bzl_library(
    name = "utils",
    srcs = ["utils.bzl"],
    deps = [
        ":feature_names",
        ":features",
        "//swift:providers",
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

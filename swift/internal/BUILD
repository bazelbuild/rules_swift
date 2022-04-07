load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

licenses(["notice"])

bzl_library(
    name = "build_settings",
    srcs = ["build_settings.bzl"],
)

bzl_library(
    name = "swift_proto_library",
    srcs = ["swift_proto_library.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":providers",
        ":swift_protoc_gen_aspect",
    ],
)

bzl_library(
    name = "swift_grpc_library",
    srcs = ["swift_grpc_library.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":feature_names",
        ":linking",
        ":proto_gen_utils",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "features",
    srcs = ["features.bzl"],
    deps = [
        ":feature_names",
        ":package_specs",
        "@bazel_skylib//lib:new_sets",
    ],
)

bzl_library(
    name = "toolchain_utils",
    srcs = ["toolchain_utils.bzl"],
)

bzl_library(
    name = "swift_module_alias",
    srcs = ["swift_module_alias.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":derived_files",
        ":linking",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "linking",
    srcs = ["linking.bzl"],
    deps = [
        ":actions",
        ":attrs",
        ":autolinking",
        ":debugging",
        ":derived_files",
        ":features",
        ":swift_clang_module_aspect",
        ":utils",
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "symbol_graph_extracting",
    srcs = ["symbol_graph_extracting.bzl"],
    deps = [
        ":actions",
        ":providers",
        ":toolchain_config",
        ":utils",
    ],
)

bzl_library(
    name = "swift_binary",
    srcs = ["swift_binary.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":linking",
        ":providers",
        ":swift_common",
        ":utils",
    ],
)

bzl_library(
    name = "swift_interop_hint",
    srcs = ["swift_interop_hint.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [":swift_common"],
)

bzl_library(
    name = "swift_symbol_graph_aspect",
    srcs = ["swift_symbol_graph_aspect.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":attrs",
        ":derived_files",
        ":features",
        ":providers",
        ":symbol_graph_extracting",
        ":toolchain_utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_import",
    srcs = ["swift_import.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":attrs",
        ":linking",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "swift_clang_module_aspect",
    srcs = ["swift_clang_module_aspect.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":attrs",
        ":compiling",
        ":derived_files",
        ":feature_names",
        ":features",
        ":module_maps",
        ":providers",
        ":toolchain_utils",
        ":utils",
        "@bazel_skylib//lib:sets",
    ],
)

bzl_library(
    name = "debugging",
    srcs = ["debugging.bzl"],
    deps = [
        ":actions",
        ":derived_files",
        ":feature_names",
        ":features",
        ":toolchain_config",
    ],
)

bzl_library(
    name = "derived_files",
    srcs = ["derived_files.bzl"],
    deps = [
        ":utils",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "package_specs",
    srcs = ["package_specs.bzl"],
)

bzl_library(
    name = "module_maps",
    srcs = ["module_maps.bzl"],
    deps = ["@bazel_skylib//lib:sets"],
)

bzl_library(
    name = "feature_names",
    srcs = ["feature_names.bzl"],
)

bzl_library(
    name = "attrs",
    srcs = ["attrs.bzl"],
    deps = [
        ":providers",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "providers",
    srcs = ["providers.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
)

bzl_library(
    name = "proto_gen_utils",
    srcs = ["proto_gen_utils.bzl"],
    deps = ["@bazel_skylib//lib:paths"],
)

bzl_library(
    name = "toolchain_config",
    srcs = ["toolchain_config.bzl"],
    deps = [
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "utils",
    srcs = ["utils.bzl"],
    deps = [
        ":providers",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "swift_extract_symbol_graph",
    srcs = ["swift_extract_symbol_graph.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":derived_files",
        ":providers",
        ":swift_symbol_graph_aspect",
    ],
)

bzl_library(
    name = "compiling",
    srcs = ["compiling.bzl"],
    deps = [
        ":actions",
        ":derived_files",
        ":feature_names",
        ":features",
        ":module_maps",
        ":providers",
        ":toolchain_config",
        ":utils",
        ":vfsoverlay",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//lib:sets",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "actions",
    srcs = ["actions.bzl"],
    deps = [
        ":features",
        ":toolchain_config",
        ":utils",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "swift_library",
    srcs = ["swift_library.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":attrs",
        ":build_settings",
        ":compiling",
        ":feature_names",
        ":linking",
        ":providers",
        ":swift_clang_module_aspect",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:sets",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "swift_protoc_gen_aspect",
    srcs = ["swift_protoc_gen_aspect.bzl"],
    deps = [
        ":attrs",
        ":feature_names",
        ":linking",
        ":proto_gen_utils",
        ":providers",
        ":swift_common",
        ":utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "swift_feature_allowlist",
    srcs = ["swift_feature_allowlist.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":package_specs",
        ":providers",
    ],
)

bzl_library(
    name = "autolinking",
    srcs = ["autolinking.bzl"],
    deps = [
        ":actions",
        ":toolchain_config",
    ],
)

bzl_library(
    name = "swift_test",
    srcs = ["swift_test.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":derived_files",
        ":feature_names",
        ":linking",
        ":providers",
        ":swift_common",
        ":swift_symbol_graph_aspect",
        ":utils",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "target_triples",
    srcs = ["target_triples.bzl"],
)

bzl_library(
    name = "swift_package_configuration",
    srcs = ["swift_package_configuration.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":package_specs",
        ":providers",
    ],
)

bzl_library(
    name = "vfsoverlay",
    srcs = ["vfsoverlay.bzl"],
)

bzl_library(
    name = "swift_common",
    srcs = ["swift_common.bzl"],
    visibility = [
        "//swift:__pkg__",
    ],
    deps = [
        ":attrs",
        ":compiling",
        ":features",
        ":linking",
        ":providers",
        ":swift_clang_module_aspect",
        ":symbol_graph_extracting",
        ":toolchain_utils",
    ],
)

bzl_library(
    name = "swift_toolchain",
    srcs = ["swift_toolchain.bzl"],
    deps = [
        ":actions",
        ":compiling",
        ":debugging",
        ":feature_names",
        ":features",
        ":providers",
        ":symbol_graph_extracting",
        ":target_triples",
        ":toolchain_config",
        ":utils",
        "@bazel_skylib//lib:partial",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "xcode_swift_toolchain",
    srcs = ["xcode_swift_toolchain.bzl"],
    deps = [
        ":actions",
        ":attrs",
        ":compiling",
        ":feature_names",
        ":features",
        ":providers",
        ":symbol_graph_extracting",
        ":target_triples",
        ":toolchain_config",
        ":utils",
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

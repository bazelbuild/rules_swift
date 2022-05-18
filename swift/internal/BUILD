load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

licenses(["notice"])

package(
    default_visibility = [
        "//swift:__subpackages__",
    ],
)

bzl_library(
    name = "actions",
    srcs = ["actions.bzl"],
    deps = [
        ":features",
        ":toolchain_config",
        ":utils",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "attrs",
    srcs = ["attrs.bzl"],
    deps = [
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
        ":actions",
        ":derived_files",
        ":feature_names",
        ":features",
        ":module_maps",
        ":providers",
        ":toolchain_config",
        ":utils",
        ":vfsoverlay",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//lib:sets",
        "@bazel_skylib//lib:types",
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
    ],
)

bzl_library(
    name = "linking",
    srcs = ["linking.bzl"],
    deps = [
        ":attrs",
        ":debugging",
        ":features",
        ":utils",
        "//swift:swift_clang_module_aspect",
        "@bazel_skylib//lib:collections",
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
    deps = ["//swift:providers"],
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
        ":feature_names",
        ":linking",
        ":proto_gen_utils",
        ":utils",
        "//swift:providers",
        "//swift:swift_common",
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
        ":derived_files",
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
        ":actions",
        ":providers",
        ":toolchain_config",
        ":utils",
    ],
)

bzl_library(
    name = "target_triples",
    srcs = ["target_triples.bzl"],
)

bzl_library(
    name = "toolchain_config",
    srcs = ["toolchain_config.bzl"],
    deps = [
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//lib:types",
    ],
)

bzl_library(
    name = "toolchain_utils",
    srcs = ["toolchain_utils.bzl"],
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
    name = "vfsoverlay",
    srcs = ["vfsoverlay.bzl"],
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

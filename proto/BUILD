load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

exports_files(["copy_swift_sources.sh.tpl"])

bzl_library(
    name = "swift_proto_common",
    srcs = ["swift_proto_common.bzl"],
    visibility = ["//visibility:public"],
    deps = [":swift_proto_utils"],
)

bzl_library(
    name = "swift_proto_compiler",
    srcs = ["swift_proto_compiler.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        ":swift_proto_utils",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "swift_proto_library",
    srcs = ["swift_proto_library.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        "//swift/internal:attrs",
        "//swift/internal:compiling",
        "//swift/internal:linking",
        "//swift/internal:swift_clang_module_aspect",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
        "@rules_proto//proto:defs",
    ],
)

bzl_library(
    name = "swift_proto_utils",
    srcs = ["swift_proto_utils.bzl"],
    visibility = ["//visibility:public"],
    deps = ["@bazel_skylib//lib:paths"],
)

bzl_library(
    name = "proto",
    srcs = ["proto.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        ":swift_proto_common",
        ":swift_proto_compiler",
        ":swift_proto_library",
        "//swift",
    ],
)

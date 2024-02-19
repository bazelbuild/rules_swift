load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

licenses(["notice"])

exports_files(["copy_swift_sources.sh.tpl"])

# swift_proto_compiler

bzl_library(
    name = "swift_proto_compiler",
    srcs = ["swift_proto_compiler.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        "//swift/internal:providers",
        "//swift/proto/internal:swift_proto_utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:paths",
    ],
)

# swift_grpc_library

bzl_library(
    name = "swift_proto_library",
    srcs = ["swift_proto_library.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":swift_proto_compiler",
        "//swift/internal:attrs",
        "//swift/internal:compiling",
        "//swift/internal:linking",
        "//swift/internal:providers",
        "//swift/internal:swift_clang_module_aspect",
        "//swift/internal:swift_common",
        "//swift/internal:utils",
        "//swift/proto/internal:swift_proto_utils",
        "@bazel_skylib//lib:dicts",
        "@rules_proto//proto:defs",
    ],
)

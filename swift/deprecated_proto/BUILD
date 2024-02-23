load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

licenses(["notice"])

bzl_library(
    name = "proto_gen_utils",
    srcs = ["proto_gen_utils.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        "//swift/internal:utils",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "swift_protoc_gen_aspect",
    srcs = ["swift_protoc_gen_aspect.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        ":proto_gen_utils",
        "//swift/internal:attrs",
        "//swift/internal:compiling",
        "//swift/internal:feature_names",
        "//swift/internal:linking",
        "//swift/internal:providers",
        "//swift/internal:swift_common",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//rules:common_settings",
        "@rules_proto//proto:defs",
    ],
)

bzl_library(
    name = "deprecated_swift_grpc_library",
    srcs = ["deprecated_swift_grpc_library.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        ":proto_gen_utils",
        ":transitions",
        "//swift/internal:actions",
        "//swift/internal:compiling",
        "//swift/internal:feature_names",
        "//swift/internal:linking",
        "//swift/internal:providers",
        "//swift/internal:swift_common",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
        "@rules_proto//proto:defs",
    ],
)

bzl_library(
    name = "deprecated_swift_proto_library",
    srcs = ["deprecated_swift_proto_library.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        ":swift_protoc_gen_aspect",
        ":transitions",
        "//swift/internal:providers",
        "@rules_proto//proto:defs",
    ],
)

bzl_library(
    name = "transitions",
    srcs = ["transitions.bzl"],
    visibility = ["//visibility:public"],
)

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load(
    "//swift/proto:swift_proto_compiler.bzl",
    "swift_proto_compiler",
)
load(
    "//swift/proto/compilers:swift_proto_compiler_macros.bzl",
    "BASE_PLUGIN_OPTIONS",
    "GRPC_VARIANT_CLIENT",
    "GRPC_VARIANT_SERVER",
    "GRPC_VARIANT_TEST_CLIENT",
    "make_grpc_swift_proto_compiler",
)

# swift_proto_compiler

swift_proto_compiler(
    name = "swift_proto",
    plugin = "//tools/protoc_wrapper:ProtoCompilerPlugin",
    plugin_name = "swift",
    plugin_options = BASE_PLUGIN_OPTIONS,
    protoc = "//tools/protoc_wrapper:protoc",
    suffixes = [".pb.swift"],
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_apple_swift_protobuf//:SwiftProtobuf",
    ],
)

# Swift GRPC

make_grpc_swift_proto_compiler(
    name = "swift_server_proto",
    variants = [GRPC_VARIANT_SERVER],
)

make_grpc_swift_proto_compiler(
    name = "swift_client_proto",
    variants = [GRPC_VARIANT_CLIENT],
)

make_grpc_swift_proto_compiler(
    name = "swift_test_client_proto",
    variants = [GRPC_VARIANT_TEST_CLIENT],
)

bzl_library(
    name = "swift_proto_compiler_macros",
    srcs = ["swift_proto_compiler_macros.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        "//swift/proto:swift_proto_compiler",
        "@bazel_skylib//lib:dicts",
    ],
)

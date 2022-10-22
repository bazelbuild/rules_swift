load("@build_bazel_apple_support//rules:universal_binary.bzl", "universal_binary")

package(default_visibility = ["//visibility:public"])

# protoc

universal_binary(
    name = "universal_protoc",
    binary = "@com_google_protobuf//:protoc",
)

alias(
    name = "protoc",
    actual = select({
        "//swift:universal_tools_config": ":universal_protoc",
        "//conditions:default": "@com_google_protobuf//:protoc",
    }),
)

# protoc-gen-grpc-swift

universal_binary(
    name = "universal_protoc-gen-grpc-swift",
    binary = "@com_github_grpc_grpc_swift//:protoc-gen-grpc-swift",
)

alias(
    name = "protoc-gen-grpc-swift",
    actual = select({
        "//swift:universal_tools_config": ":universal_protoc-gen-grpc-swift",
        "//conditions:default": "@com_github_grpc_grpc_swift//:protoc-gen-grpc-swift",
    }),
)

# ProtoCompilerPlugin

universal_binary(
    name = "universal_ProtoCompilerPlugin",
    binary = "@com_github_apple_swift_protobuf//:ProtoCompilerPlugin",
)

alias(
    name = "ProtoCompilerPlugin",
    actual = select({
        "//swift:universal_tools_config": ":universal_ProtoCompilerPlugin",
        "//conditions:default": "@com_github_apple_swift_protobuf//:ProtoCompilerPlugin",
    }),
)

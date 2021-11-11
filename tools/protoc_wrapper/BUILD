load("@build_bazel_apple_support//rules:universal_binary.bzl", "universal_binary")

package(default_visibility = ["//visibility:public"])

universal_binary(
    name = "universal_protoc",
    binary = "@com_google_protobuf//:protoc",
)

alias(
    name = "protoc_wrapper",
    actual = select({
        "//swift:universal_tools_config": ":universal_protoc",
        "//conditions:default": "@com_google_protobuf//:protoc",
    }),
)

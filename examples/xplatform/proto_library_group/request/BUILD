load("@protobuf//bazel:proto_library.bzl", "proto_library")

proto_library(
    name = "request_proto",
    srcs = glob(["*.proto"]),
    visibility = ["//visibility:public"],
    deps = [
        "@protobuf//:any_proto",
    ],
)

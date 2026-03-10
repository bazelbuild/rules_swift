load("@protobuf//bazel:proto_library.bzl", "proto_library")

proto_library(
    name = "response_proto",
    srcs = glob(["*.proto"]),
    visibility = ["//visibility:public"],
    deps = ["//examples/xplatform/proto_library_group/request:request_proto"],
)

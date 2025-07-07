load("@com_google_protobuf//bazel:proto_library.bzl", "proto_library")

proto_library(
    name = "request_proto",
    srcs = glob(["*.proto"]),
    visibility = ["//visibility:public"],
    deps = [
        "@com_google_protobuf//:any_proto",
    ],
)

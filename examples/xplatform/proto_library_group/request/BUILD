load(
    "@rules_proto//proto:defs.bzl",
    "proto_library",
)

proto_library(
    name = "request_proto",
    srcs = glob(["*.proto"]),
    deps = [
        "@com_google_protobuf//:any_proto",
    ],
    visibility = ["//visibility:public"],
)

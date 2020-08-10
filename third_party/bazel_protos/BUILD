load("@rules_proto//proto:defs.bzl", "proto_library")
load("@rules_cc//cc:defs.bzl", "cc_proto_library")

licenses(["notice"])

proto_library(
    name = "worker_protocol_proto",
    srcs = ["worker_protocol.proto"],
)

cc_proto_library(
    name = "worker_protocol_cc_proto",
    visibility = ["//tools/worker:__pkg__"],
    deps = [":worker_protocol_proto"],
)

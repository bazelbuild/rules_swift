load(
    "//swift:swift.bzl",
    "swift_binary",
    "swift_proto_library",
)

licenses(["notice"])

proto_library(
    name = "example_proto",
    srcs = ["example.proto"],
)

swift_proto_library(
    name = "example_proto_swift",
    deps = [":example_proto"],
)

swift_binary(
    name = "proto",
    srcs = ["main.swift"],
    deps = [":example_proto_swift"],
)

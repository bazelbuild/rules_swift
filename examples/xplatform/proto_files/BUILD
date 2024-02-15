load(
    "@rules_proto//proto:defs.bzl",
    "proto_library",
)
load(
    "//proto:proto.bzl",
    "swift_proto_library",
)
load(
    "//swift:swift.bzl",
    "swift_binary",
)

proto_library(
    name = "message_1_proto",
    srcs = [
        "message_1.proto",
    ],
)

proto_library(
    name = "message_2_proto",
    srcs = [
        "message_2.proto",
    ],
    deps = [
        ":message_1_proto",
    ],
)

swift_proto_library(
    name = "messages_swift_proto",
    module_name = "Messages",
    protos = [
        ":message_1_proto",
        ":message_2_proto",
    ],
)

swift_binary(
    name = "proto_files_example",
    srcs = [
        "main.swift",
    ],
    deps = [
        ":messages_swift_proto",
    ],
)

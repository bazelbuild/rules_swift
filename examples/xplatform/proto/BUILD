load("@rules_proto//proto:defs.bzl", "proto_library")
load(
    "//swift:swift.bzl",
    "swift_binary",
    "swift_proto_library",
)

licenses(["notice"])

proto_library(
    name = "example_proto",
    srcs = ["example.proto"],
    deps = [
        "@com_google_protobuf//:api_proto",
    ],
)

swift_proto_library(
    name = "example_proto_swift",
    deps = [":example_proto"],
)

proto_library(
    name = "example_path_to_underscores_proto",
    srcs = [
        "PathToUnderscores/message_1/message.proto",
        "PathToUnderscores/message_2/message.proto",
    ],
    features = ["swift.generate_path_to_underscores_from_proto_files"],
    strip_import_prefix = "PathToUnderscores",
)

swift_proto_library(
    name = "example_path_to_underscores_proto_swift",
    deps = [":example_path_to_underscores_proto"],
)

swift_binary(
    name = "proto",
    srcs = ["main.swift"],
    deps = [
        ":example_path_to_underscores_proto_swift",
        ":example_proto_swift",
    ],
)

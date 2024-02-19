load(
    "//proto:proto.bzl",
    "swift_proto_library",
)

swift_proto_library(
    name = "example_proto_swift",
    compilers = [
        "//examples/xplatform/custom_swift_proto_compiler/compiler",
    ],
    protos = ["//examples/xplatform/custom_swift_proto_compiler/protos:example_proto"],
)

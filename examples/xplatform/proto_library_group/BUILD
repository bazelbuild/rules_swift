load(
    "//proto:proto.bzl",
    "swift_proto_library_group",
)
load(
    "//swift:swift.bzl",
    "swift_binary",
)

swift_proto_library_group(
    name = "proto_library_group_swift_proto",
    protos = [
        "//examples/xplatform/proto_library_group/package_1:package_1_proto",
        "//examples/xplatform/proto_library_group/package_2:package_2_proto"
    ],
)

swift_binary(
    name = "proto_library_group_example",
    srcs = ["main.swift"],
    deps = [
        ":proto_library_group_swift_proto",
    ],
)

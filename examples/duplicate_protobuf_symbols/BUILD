load("//swift:swift.bzl", "swift_library", "swift_binary")

swift_library(
    name = "local_swift_protobuf",
    srcs = ["File.swift"],
    deps = [
        "@com_github_apple_swift_protobuf//:SwiftProtobuf"
    ]
)

swift_binary(
    name = "main",
    srcs = ["main.swift"],
    deps = [
        ":local_swift_protobuf",
        "@transitive_swift_protobuf_repro//:example_proto_swift"
    ]
)

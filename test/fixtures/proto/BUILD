load(
    "//swift:swift_proto_library.bzl",
    "swift_proto_library",
)
load("//third_party/protobuf/bazel:proto_library.bzl", "proto_library")

package(
    default_visibility = [
        "//test:__subpackages__",
    ],
)

licenses(["notice"])

proto_library(
    name = "leaf_proto",
    srcs = ["leaf.proto"],
    tags = ["manual"],
)

swift_proto_library(
    name = "leaf_swift_proto",
    tags = ["manual"],
    deps = [":leaf_proto"],
)

# A collector `proto_library` without `srcs` that re-exports `:leaf_proto`.
proto_library(
    name = "collector_proto",
    tags = ["manual"],
    deps = [":leaf_proto"],
)

proto_library(
    name = "top_proto",
    srcs = ["top.proto"],
    tags = ["manual"],
    deps = [":collector_proto"],
)

swift_proto_library(
    name = "top_swift_proto",
    tags = ["manual"],
    deps = [":top_proto"],
)

swift_proto_library(
    name = "invalid_collector_swift_proto",
    tags = ["manual"],
    deps = [":collector_proto"],
)

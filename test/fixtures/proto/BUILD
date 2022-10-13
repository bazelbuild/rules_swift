load("//swift:swift.bzl", "swift_proto_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load("@rules_proto//proto:defs.bzl", "proto_library")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing swift_proto_library

proto_library(
    name = "full_path_proto",
    srcs = [
      "FullPath/message_1.proto",
      "FullPath/message_2.proto",
    ],
    strip_import_prefix = "FullPath",
    tags = FIXTURE_TAGS,
)

swift_proto_library(
    name = "full_path_proto_swift",
    deps = [":full_path_proto"],
    tags = FIXTURE_TAGS,
)

proto_library(
    name = "path_to_underscores_proto",
    srcs = [
      "PathToUnderscores/message_1/message.proto",
      "PathToUnderscores/message_2/message.proto",
    ],
    strip_import_prefix = "PathToUnderscores",
    tags = FIXTURE_TAGS,
)

swift_proto_library(
    name = "path_to_underscores_proto_swift",
    deps = [":path_to_underscores_proto"],
    tags = FIXTURE_TAGS,
)

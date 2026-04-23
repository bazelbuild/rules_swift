load("@protobuf//bazel:proto_library.bzl", "proto_library")
load("//proto:swift_proto_library.bzl", "swift_proto_library")
load("//proto:swift_proto_library_group.bzl", "swift_proto_library_group")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_compiler_plugin.bzl", "swift_compiler_plugin")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(default_visibility = ["//test:__subpackages__"])

swift_library(
    name = "library",
    srcs = ["empty.swift"],
    minimum_os_version = "10.15",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "library_with_selected_minimum_os_version",
    srcs = ["empty.swift"],
    minimum_os_version = select({
        "@platforms//os:ios": "13.0",
        "@platforms//os:macos": "10.15",
        "//conditions:default": "",
    }),
    tags = FIXTURE_TAGS,
)

platform(
    name = "macos_arm64_platform",
    constraint_values = [
        "@platforms//cpu:arm64",
        "@platforms//os:macos",
    ],
)

platform(
    name = "ios_arm64_platform",
    constraint_values = [
        "@platforms//cpu:arm64",
        "@platforms//os:ios",
    ],
)

swift_binary(
    name = "binary",
    srcs = ["empty.swift"],
    minimum_os_version = "10.15",
    tags = FIXTURE_TAGS,
)

swift_compiler_plugin(
    name = "compiler_plugin",
    srcs = ["empty.swift"],
    minimum_os_version = "10.15",
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "test",
    srcs = ["empty.swift"],
    discover_tests = False,
    minimum_os_version = "10.15",
    tags = FIXTURE_TAGS,
)

proto_library(
    name = "message_proto",
    srcs = ["message.proto"],
    tags = FIXTURE_TAGS,
)

swift_proto_library(
    name = "message_swift_proto",
    minimum_os_version = "10.15",
    protos = [":message_proto"],
    tags = FIXTURE_TAGS,
)

swift_proto_library_group(
    name = "message_swift_proto_group",
    proto = ":message_proto",
    tags = FIXTURE_TAGS,
)

load("//swift:swift_binary.bzl", "swift_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_binary(
    name = "bin",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
)

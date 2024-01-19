load("//swift:swift.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "first",
    srcs = ["first.swift"],
    module_name = "first",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "second",
    srcs = ["second.swift"],
    module_name = "second",
    tags = FIXTURE_TAGS,
    deps = ["first"],
)

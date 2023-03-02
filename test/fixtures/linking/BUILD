load("//swift:swift.bzl", "swift_binary", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":fake_framework.bzl", "fake_framework")

package(
    default_visibility = ["//test:__subpackages__"],
)

fake_framework(
    name = "framework",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "bin",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
    deps = [":framework"],
)

swift_library(
    name = "lib",
    srcs = ["lib.swift"],
    tags = FIXTURE_TAGS,
)

cc_binary(
    name = "cc_bin",
    srcs = ["main.cc"],
    tags = FIXTURE_TAGS,
    deps = [":lib"],
)

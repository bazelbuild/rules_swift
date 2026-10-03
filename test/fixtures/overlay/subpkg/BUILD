load(
    "//swift:swift_overlay.bzl",
    "swift_overlay",
)
load(
    "//test/fixtures:common.bzl",
    "FIXTURE_TAGS",
)

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_overlay(
    name = "subpkg_overlay",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

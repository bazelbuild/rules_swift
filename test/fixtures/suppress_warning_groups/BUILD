load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_overlay.bzl", "swift_overlay")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

swift_library(
    name = "single_category",
    srcs = ["Library.swift"],
    suppress_warning_groups = ["DeprecatedDeclaration"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "multiple_categories",
    srcs = ["Library.swift"],
    suppress_warning_groups = [
        "DeprecatedDeclaration",
        "ImplementationOnlyDeprecated",
    ],
    tags = FIXTURE_TAGS,
)

swift_overlay(
    name = "overlay",
    srcs = ["Overlay.swift"],
    suppress_warning_groups = ["OverlayDeprecated"],
    tags = FIXTURE_TAGS,
)

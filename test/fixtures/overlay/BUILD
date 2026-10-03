load("@rules_cc//cc:cc_library.bzl", "cc_library")
load(
    "//swift:swift_interop_hint.bzl",
    "swift_interop_hint",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_overlay.bzl",
    "swift_overlay",
)
load(
    "//test/fixtures:common.bzl",
    "FIXTURE_TAGS",
    "forward_swift_info_from_swift_clang_module_aspect",
)

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "public_dep",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "private_dep",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_overlay(
    name = "overlay",
    srcs = ["Empty.swift"],
    private_deps = [":private_dep"],
    tags = FIXTURE_TAGS,
    deps = [":public_dep"],
)

cc_library(
    name = "cc_with_overlay",
    hdrs = ["header.h"],
    aspect_hints = [":overlay"],
    tags = FIXTURE_TAGS,
)

forward_swift_info_from_swift_clang_module_aspect(
    name = "cc_with_overlay_swift_info",
    target = ":cc_with_overlay",
)

swift_library(
    name = "downstream_of_overlay",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":cc_with_overlay"],
)

swift_interop_hint(
    name = "custom_module_hint",
    module_name = "CustomOverlayMod",
    tags = FIXTURE_TAGS,
)

swift_overlay(
    name = "custom_overlay",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "cc_with_custom_module_and_overlay",
    hdrs = ["header.h"],
    aspect_hints = [
        ":custom_module_hint",
        ":custom_overlay",
    ],
    tags = FIXTURE_TAGS,
)

forward_swift_info_from_swift_clang_module_aspect(
    name = "cc_with_custom_module_and_overlay_swift_info",
    target = ":cc_with_custom_module_and_overlay",
)

cc_library(
    name = "invalid_cross_pkg_cc",
    hdrs = ["header.h"],
    aspect_hints = [
        "//test/fixtures/overlay/subpkg:subpkg_overlay",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "invalid_cross_pkg_swift",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":invalid_cross_pkg_cc"],
)

swift_overlay(
    name = "overlay_1",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_overlay(
    name = "overlay_2",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "invalid_multiple_overlays_cc",
    hdrs = ["header.h"],
    aspect_hints = [
        ":overlay_1",
        ":overlay_2",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "invalid_multiple_overlays_swift",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":invalid_multiple_overlays_cc"],
)

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
    "//swift:swift_test.bzl",
    "swift_test",
)

licenses(["notice"])

cc_library(
    name = "retro_library",
    srcs = ["retro_library.c"],
    hdrs = ["retro_library.h"],
    aspect_hints = [
        ":retro_library_swift_hint",
        ":retro_library_swift_overlay",
    ],
)

swift_interop_hint(
    name = "retro_library_swift_hint",
    module_name = "RetroLibrary",
)

swift_library(
    name = "orientation",
    srcs = ["Orientation.swift"],
    module_name = "OrientationModule",
)

swift_overlay(
    name = "retro_library_swift_overlay",
    srcs = ["RetroLibraryOverlay.swift"],
    deps = [":orientation"],
)

swift_test(
    name = "retro_test",
    srcs = ["RetroTest.swift"],
    deps = [
        ":orientation",
        ":retro_library",
    ],
)

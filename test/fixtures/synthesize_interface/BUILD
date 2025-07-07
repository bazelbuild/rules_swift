load("@rules_cc//cc:cc_library.bzl", "cc_library")
load(
    "//swift:swift_interop_hint.bzl",
    "swift_interop_hint",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(
    "//test/rules:synthesize_interface_applier.bzl",
    "synthesize_interface_applier",
)

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

cc_library(
    name = "c_module",
    hdrs = ["header.h"],
    aspect_hints = [":c_module_swift_hint"],
    tags = FIXTURE_TAGS,
)

swift_interop_hint(
    name = "c_module_swift_hint",
    tags = FIXTURE_TAGS,
)

synthesize_interface_applier(
    name = "synthesized_interface",
    tags = FIXTURE_TAGS,
    target = ":c_module",
)

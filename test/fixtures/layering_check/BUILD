load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_overlay.bzl", "swift_overlay")
load("//test:transitions.bzl", "transition_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_interop_hint(
    name = "SelfImporting_hint",
    module_name = "SelfImporting",
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "SelfImporting",
    srcs = ["SelfImporting.c"],
    hdrs = ["SelfImporting.h"],
    aspect_hints = [
        ":SelfImporting_hint",
        ":SelfImporting_overlay",
    ],
    tags = FIXTURE_TAGS,
)

swift_overlay(
    name = "SelfImporting_overlay",
    srcs = ["SelfImportingOverlay.swift"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "self_importing_consumer",
    srcs = ["SelfImportingConsumer.swift"],
    tags = FIXTURE_TAGS,
    deps = [":SelfImporting"],
)

transition_binary(
    name = "self_importing_consumer_layering_check",
    tags = FIXTURE_TAGS,
    target = ":self_importing_consumer",
    transitive_features = ["swift.layering_check_swift"],
)

swift_library(
    name = "TransitiveDependency",
    srcs = ["TransitiveDependency.swift"],
    module_name = "TransitiveDependency",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "DirectDependency",
    srcs = ["DirectDependency.swift"],
    module_name = "DirectDependency",
    tags = FIXTURE_TAGS,
    deps = [":TransitiveDependency"],
)

swift_binary(
    name = "layering_violation",
    srcs = ["LayeringViolation.swift"],
    features = ["swift.layering_check_swift"],
    tags = FIXTURE_TAGS,
    deps = [":DirectDependency"],
)

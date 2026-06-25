load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_overlay.bzl", "swift_overlay")
load("//test:transitions.bzl", "transition_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
    features = ["swift.layering_check_swift"],
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

swift_library(
    name = "foundation_consumer",
    srcs = ["FoundationConsumer.swift"],
    module_name = "FoundationConsumer",
    tags = FIXTURE_TAGS,
)

transition_binary(
    name = "foundation_consumer_default_precompiled_modules",
    tags = FIXTURE_TAGS,
    target = ":foundation_consumer",
    target_compatible_with = select({
        "@apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
    ],
)

transition_binary(
    name = "foundation_consumer_violation_precompiled_modules",
    tags = FIXTURE_TAGS,
    target = ":foundation_consumer",
    target_compatible_with = select({
        "@apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

swift_library(
    name = "TransitiveDependency",
    srcs = ["TransitiveDependency.swift"],
    module_name = "TransitiveDependency",
    tags = FIXTURE_TAGS,
    deps = ["@system_sdk//:SwiftShims"],
)

swift_library(
    name = "DirectDependency",
    srcs = ["DirectDependency.swift"],
    module_name = "DirectDependency",
    tags = FIXTURE_TAGS,
    deps = [":TransitiveDependency"],
)

swift_library(
    name = "layering_violation",
    srcs = ["LayeringViolation.swift"],
    module_name = "LayeringViolation",
    tags = FIXTURE_TAGS,
    deps = [":DirectDependency"],
)

swift_library(
    name = "unused_dependency",
    srcs = ["UnusedDependency.swift"],
    module_name = "UnusedDependency",
    tags = FIXTURE_TAGS,
    deps = [":DirectDependency"],
)

transition_binary(
    name = "layering_violation_explicit_modules",
    tags = FIXTURE_TAGS,
    target = ":layering_violation",
    target_compatible_with = select({
        "@apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.use_explicit_swift_module_map",
        "-swift.add_default_precompiled_modules",
    ],
)

transition_binary(
    name = "layering_violation_explicit_modules_default_precompiled_modules",
    tags = FIXTURE_TAGS,
    target = ":layering_violation",
    target_compatible_with = select({
        "@apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.use_explicit_swift_module_map",
        "swift.add_default_precompiled_modules",
    ],
)

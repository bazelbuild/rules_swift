load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":force_features.bzl", "force_features_binary")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

swift_binary(
    name = "hello",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "hello_with_explicit_deps_bin",
    srcs = ["main.swift"],
    features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        "@apple_sdk//:Foundation",
    ],
)

force_features_binary(
    name = "hello_with_explicit_deps_transitioned",
    binary = ":hello_with_explicit_deps_bin",
    tags = FIXTURE_TAGS,
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

swift_interop_hint(
    name = "Greeter_hint",
    module_name = "Greeter",
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "Greeter",
    srcs = ["Greeter.m"],
    hdrs = ["Greeter.h"],
    aspect_hints = [":Greeter_hint"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = ["@apple_sdk//:Foundation"],
)

swift_binary(
    name = "objc_interop_bin",
    srcs = ["greeter_main.swift"],
    tags = FIXTURE_TAGS,
    deps = [
        ":Greeter",
    ],
)

force_features_binary(
    name = "objc_interop_bin_transitioned",
    binary = ":objc_interop_bin",
    tags = FIXTURE_TAGS,
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

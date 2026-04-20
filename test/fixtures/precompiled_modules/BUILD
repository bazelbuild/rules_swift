load("//swift:swift_binary.bzl", "swift_binary")
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

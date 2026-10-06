load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("//mixed_language:mixed_language_library.bzl", "mixed_language_library")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":strict_includes.bzl", "strict_include_module")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

objc_library(
    name = "TestOnlyDep",
    testonly = True,
    hdrs = ["TestOnlyDep.h"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

mixed_language_library(
    name = "MixedLibraryWithTestOnlyDeps",
    testonly = True,
    hdrs = ["MixedLibrary.h"],
    clang_srcs = ["MixedLibrary.m"],
    module_name = "MixedLibraryWithTestOnlyDeps",
    swift_srcs = ["MixedLibrary.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [":TestOnlyDep"],
)

strict_include_module(
    name = "StrictTransitive",
    strict_includes = ["strict/transitive"],
    tags = FIXTURE_TAGS,
)

strict_include_module(
    name = "StrictPublic",
    strict_includes = ["strict/public"],
    tags = FIXTURE_TAGS,
    deps = [":StrictTransitive"],
)

strict_include_module(
    name = "StrictPrivate",
    strict_includes = ["strict/private"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "StrictMixedLibrary",
    srcs = [
        "Empty.m",
        "Empty.swift",
    ],
    features = ["swift.supports_private_deps"],
    private_deps = [":StrictPrivate"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":StrictPublic"],
)

swift_library(
    name = "StrictMixedConsumer",
    srcs = [
        "Empty.m",
        "Empty.swift",
    ],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":StrictMixedLibrary"],
)

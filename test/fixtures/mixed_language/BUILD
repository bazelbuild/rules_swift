load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("//mixed_language:mixed_language_library.bzl", "mixed_language_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

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

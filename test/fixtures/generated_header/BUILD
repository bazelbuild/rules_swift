load("@rules_cc//cc:objc_library.bzl", "objc_library")
load(
    "//swift:swift_interop_hint.bzl",
    "swift_interop_hint",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "no_header",
    srcs = ["Empty.swift"],
    generates_header = False,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "auto_header",
    srcs = ["Empty.swift"],
    generates_header = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "explicit_header",
    srcs = ["Empty.swift"],
    generated_header_name = "SomeOtherName.h",
    generates_header = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "invalid_extension",
    srcs = ["Empty.swift"],
    generated_header_name = "Invalid.extension",
    generates_header = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "valid_path_separator",
    srcs = ["Empty.swift"],
    generated_header_name = "Valid/Separator.h",
    generates_header = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "invalid_attribute_combination",
    srcs = ["Empty.swift"],
    generated_header_name = "SomeOtherName.h",
    generates_header = False,
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "c_dependency",
    srcs = ["CDependency.m"],
    hdrs = ["CDependency.h"],
    aspect_hints = [":c_dependency_hint"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = ["@system_sdk//:Foundation"],
)

swift_interop_hint(
    name = "c_dependency_hint",
    module_name = "GeneratedHeaderCDependency",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "generated_header_with_c_dep",
    srcs = ["UsesCDependency.swift"],
    generates_header = True,
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":c_dependency"],
)

objc_library(
    name = "objc_consumer_of_generated_header",
    srcs = ["ObjcConsumer.m"],
    enable_modules = True,
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":generated_header_with_c_dep"],
)

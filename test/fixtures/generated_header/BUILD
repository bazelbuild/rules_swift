load("//swift:swift.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "auto_header",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "explicit_header",
    srcs = ["Empty.swift"],
    generated_header_name = "SomeOtherName.h",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "invalid_extension",
    srcs = ["Empty.swift"],
    generated_header_name = "Invalid.extension",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "valid_path_separator",
    srcs = ["Empty.swift"],
    generated_header_name = "Valid/Separator.h",
    tags = FIXTURE_TAGS,
)

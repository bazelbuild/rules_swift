load("//swift:swift_binary.bzl", "swift_binary")
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing serializing debug options.

swift_library(
    name = "simple",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "binary",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "module_path_binary",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":simple"],
)

load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

###############################################################################
# Fixtures for testing minimum_os_version attribute.

# Library with explicit minimum_os_version
swift_library(
    name = "lib_with_min_os",
    srcs = ["empty.swift"],
    minimum_os_version = "17.0",
    tags = FIXTURE_TAGS,
)

# Binary with explicit minimum_os_version
swift_binary(
    name = "bin_with_min_os",
    srcs = ["empty.swift"],
    minimum_os_version = "17.0",
    tags = FIXTURE_TAGS,
)

# Test with explicit minimum_os_version
swift_test(
    name = "test_with_min_os",
    srcs = ["empty.swift"],
    discover_tests = False,
    minimum_os_version = "17.0",
    tags = FIXTURE_TAGS,
)

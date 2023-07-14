load("//swift:swift.bzl", "swift_binary", "swift_library", "swift_test")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

###############################################################################
# Fixtures for testing serializing debug options.

swift_library(
    name = "no_package_name",
    srcs = ["empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "lib_package_name",
    package_name = "lib",
    srcs = ["empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "bin_package_name",
    package_name = "bin",
    srcs = ["empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "test_package_name",
    package_name = "test",
    srcs = ["empty.swift"],
    tags = FIXTURE_TAGS,
)

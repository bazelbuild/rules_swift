load("//swift:swift.bzl", "swift_library", "swift_test")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing link argument passing when a library is marked as testonly.

swift_library(
    name = "simple",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "simple_testonly",
    srcs = ["EmptyTestLibrary.swift"],
    tags = FIXTURE_TAGS,
    testonly = True
)

swift_test(
    name = "simple_test",
    srcs = ["EmptyTest.swift"],
    tags = FIXTURE_TAGS,
)

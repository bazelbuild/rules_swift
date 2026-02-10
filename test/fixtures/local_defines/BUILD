load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load(
    "//test/fixtures:common.bzl",
    "FIXTURE_TAGS",
)

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "lib_with_local_defines",
    srcs = ["empty.swift"],
    defines = ["PROPAGATED_BAR"],
    local_defines = ["LOCAL_FOO"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "lib_dependent",
    srcs = ["empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":lib_with_local_defines"],
)

swift_binary(
    name = "bin_with_local_defines",
    srcs = ["empty.swift"],
    local_defines = ["BIN_LOCAL_FOO"],
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "test_with_local_defines",
    srcs = ["empty.swift"],
    discover_tests = False,  # Turn off to avoid two compiles and thus the test can't detect the flags correctly.
    local_defines = ["TEST_LOCAL_FOO"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "mixed_lib_with_local_defines",
    srcs = [
        "mixed_lib.h",
        "mixed_lib.m",
        "mixed_lib.swift",
    ],
    defines = ["PROPAGATED_BAR"],
    local_defines = ["LOCAL_FOO"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "mixed_lib_dependent",
    srcs = [
        "dependent.m",
        "empty.swift",
    ],
    tags = FIXTURE_TAGS,
    deps = [
        ":mixed_lib_with_local_defines",
    ],
)

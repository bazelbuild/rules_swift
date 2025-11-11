load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":fake_framework.bzl", "fake_framework")

package(
    default_visibility = ["//test:__subpackages__"],
)

fake_framework(
    name = "framework",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "bin",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
    deps = [":framework"],
)

swift_library(
    name = "lib",
    srcs = ["lib.swift"],
    tags = FIXTURE_TAGS,
)

cc_binary(
    name = "cc_bin",
    srcs = ["main.cc"],
    tags = FIXTURE_TAGS,
    deps = [":lib"],
)

swift_binary(
    name = "bin_with_additional_linker_inputs",
    srcs = ["main.swift"],
    additional_linker_inputs = ["test_data.bin"],
    linkopts = [
        "-Wl,-sectcreate,__TEXT,__test_section,$(execpath test_data.bin)",
    ],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "bin_with_empty_additional_linker_inputs",
    srcs = ["main.swift"],
    additional_linker_inputs = [],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "bin_without_additional_linker_inputs",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
)

bzl_library(
    name = "fake_framework",
    srcs = ["fake_framework.bzl"],
    deps = [
        "@bazel_tools//tools/cpp:toolchain_utils.bzl",
        "@rules_cc//cc/common",
    ],
)

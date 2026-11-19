load("@bazel_skylib//lib:selects.bzl", "selects")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_test.bzl", "cc_test")

package(default_visibility = ["//tools/worker:__pkg__"])

licenses(["notice"])

cc_library(
    name = "xcode_symlink_test_fixture",
    testonly = True,
    hdrs = ["xcode_symlink_test_fixture.h"],
    deps = [
        ":temp_file",
        "@googletest//:gtest",
    ],
)

cc_test(
    name = "bazel_substitutions_test",
    size = "small",
    srcs = ["bazel_substitutions_test.cc"],
    copts = selects.with_or({
        ("//tools:clang-cl", "//tools:msvc"): ["/std:c++17"],
        "//conditions:default": ["-std=c++17"],
    }),
    deps = [
        ":bazel_substitutions",
        ":xcode_symlink_test_fixture",
        "@googletest//:gtest_main",
    ],
)

cc_library(
    name = "bazel_substitutions",
    srcs = ["bazel_substitutions.cc"],
    hdrs = ["bazel_substitutions.h"],
    copts = selects.with_or({
        ("//tools:clang-cl", "//tools:msvc"): [
            "/std:c++17",
        ],
        "//conditions:default": [
            "-std=c++17",
        ],
    }),
    deps = [
        ":process",
    ],
)

cc_library(
    name = "process",
    srcs = ["process.cc"],
    hdrs = ["process.h"],
    copts = selects.with_or({
        ("//tools:clang-cl", "//tools:msvc"): [
            "/std:c++17",
        ],
        "//conditions:default": [
            "-std=c++17",
        ],
    }),
)

cc_library(
    name = "color",
    hdrs = ["color.h"],
    copts = selects.with_or({
        ("//tools:clang-cl", "//tools:msvc"): [
            "/std:c++17",
        ],
        "//conditions:default": [
            "-std=c++17",
        ],
    }),
    deps = [
        "@abseil-cpp//absl/strings",
    ],
)

cc_library(
    name = "file_system",
    srcs = ["file_system.cc"],
    hdrs = ["file_system.h"],
    copts = selects.with_or({
        ("//tools:clang-cl", "//tools:msvc"): [
            "/std:c++17",
        ],
        "//conditions:default": [
            "-std=c++17",
        ],
    }),
    deps = [
        "@abseil-cpp//absl/strings",
    ],
)

cc_library(
    name = "path_utils",
    srcs = ["path_utils.cc"],
    hdrs = ["path_utils.h"],
    copts = selects.with_or({
        ("//tools:clang-cl", "//tools:msvc"): [
            "/std:c++17",
        ],
        "//conditions:default": [
            "-std=c++17",
        ],
    }),
    deps = [
        "@abseil-cpp//absl/strings",
    ],
)

cc_library(
    name = "target_triple",
    hdrs = ["target_triple.h"],
    deps = ["@abseil-cpp//absl/strings"],
)

cc_library(
    name = "temp_file",
    hdrs = ["temp_file.h"],
    copts = selects.with_or({
        ("//tools:clang-cl", "//tools:msvc"): [
            "/std:c++17",
        ],
        "//conditions:default": [
            "-std=c++17",
        ],
    }),
)

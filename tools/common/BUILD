load("@bazel_skylib//lib:selects.bzl", "selects")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//tools/worker:__pkg__"])

licenses(["notice"])

cc_library(
    name = "bazel_substitutions",
    srcs = ["bazel_substitutions.cc"],
    hdrs = ["bazel_substitutions.h"],
    copts = select({
        "//tools:clang-cl": [
            "-Xclang",
            "-fno-split-cold-code",
            "/std:c++17",
        ],
        "//tools:msvc": [
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

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = True,
    srcs = glob(["**"]),
    visibility = [
        "//tools:__pkg__",
    ],
)

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
            "-Xclang=-fno-split-cold-code",
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
    deps = [
        ":temp_file",
        "@abseil-cpp//absl/container:flat_hash_map",
        "@abseil-cpp//absl/status:statusor",
    ],
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
    deps = [
        "@abseil-cpp//absl/strings",
    ],
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
        ":path_utils",
        ":status",
        "@abseil-cpp//absl/cleanup",
        "@abseil-cpp//absl/status:statusor",
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
    name = "status",
    srcs = ["status.cc"],
    hdrs = ["status.h"],
    copts = selects.with_or({
        ("//tools:clang-cl", "//tools:msvc"): [
            "/std:c++17",
        ],
        "//conditions:default": [
            "-std=c++17",
        ],
    }),
    deps = [
        "@abseil-cpp//absl/status",
        "@abseil-cpp//absl/strings",
    ],
)

cc_library(
    name = "target_triple",
    hdrs = ["target_triple.h"],
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

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = True,
    srcs = glob(["**"]),
    visibility = [
        "//tools:__pkg__",
    ],
)

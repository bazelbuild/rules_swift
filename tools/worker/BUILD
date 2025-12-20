load("@build_bazel_apple_support//rules:universal_binary.bzl", "universal_binary")
load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

licenses(["notice"])

cc_library(
    name = "swift_runner",
    srcs = [
        "output_file_map.cc",
        "swift_runner.cc",
    ],
    hdrs = [
        "output_file_map.h",
        "swift_runner.h",
    ],
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
    data = select({
        "@build_bazel_apple_support//constraints:apple": [
            "@build_bazel_rules_swift_index_import_5_8//:index_import",
            "@build_bazel_rules_swift_index_import_6_1//:index_import",
        ],
        "//conditions:default": [],
    }),
    deps = [
        "//tools/common:bazel_substitutions",
        "//tools/common:color",
        "//tools/common:file_system",
        "//tools/common:path_utils",
        "//tools/common:process",
        "//tools/common:target_triple",
        "//tools/common:temp_file",
        "@abseil-cpp//absl/base:nullability",
        "@abseil-cpp//absl/container:btree",
        "@abseil-cpp//absl/container:flat_hash_map",
        "@abseil-cpp//absl/container:flat_hash_set",
        "@abseil-cpp//absl/status",
        "@abseil-cpp//absl/status:statusor",
        "@abseil-cpp//absl/strings",
        "@com_github_nlohmann_json//:json",
        "@re2",
    ],
)

cc_binary(
    name = "worker",
    srcs = ["main.cc"],
    visibility = ["//visibility:public"],
    deps = [
        ":swift_runner",
        "//tools/common:process",
        "@bazel_tools//tools/cpp/runfiles",
    ],
)

universal_binary(
    name = "universal_worker",
    binary = ":worker",
    visibility = ["//visibility:public"],
)

alias(
    name = "worker_wrapper",
    actual = select({
        "//swift:universal_tools_config": ":universal_worker",
        "//conditions:default": ":worker",
    }),
    visibility = ["//visibility:public"],
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

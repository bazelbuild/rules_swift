load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

bzl_library(
    name = "swift_toolchain",
    srcs = ["swift_toolchain.bzl"],
    deps = [
        "//swift:providers",
        "//swift/internal:actions",
        "//swift/internal:compiling",
        "//swift/internal:debugging",
        "//swift/internal:feature_names",
        "//swift/internal:features",
        "//swift/internal:symbol_graph_extracting",
        "//swift/internal:target_triples",
        "//swift/internal:toolchain_config",
        "//swift/internal:utils",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "xcode_swift_toolchain",
    srcs = ["xcode_swift_toolchain.bzl"],
    deps = [
        "//swift:providers",
        "//swift/internal:actions",
        "//swift/internal:attrs",
        "//swift/internal:compiling",
        "//swift/internal:feature_names",
        "//swift/internal:features",
        "//swift/internal:symbol_graph_extracting",
        "//swift/internal:target_triples",
        "//swift/internal:toolchain_config",
        "//swift/internal:utils",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:paths",
    ],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]),
    visibility = [
        "//swift:__pkg__",
    ],
)

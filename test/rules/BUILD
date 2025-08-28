load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

bzl_library(
    name = "starlark_tests_bzls",
    srcs = glob(["*.bzl"]),
    visibility = [
        "//test:__pkg__",
    ],
    deps = [
        "//swift:providers",
        "//swift:swift_synthesize_interface_aspect",
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:types",
        "@bazel_skylib//lib:unittest",
        "@rules_cc//cc/common",
    ],
)

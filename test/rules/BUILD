load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

bzl_library(
    name = "starlark_tests_bzls",
    srcs = glob(["*.bzl"]),
    visibility = [
        "//test:__pkg__",
    ],
    deps = [
        "//swift",
        "@bazel_skylib//lib:collections",
        "@bazel_skylib//lib:types",
        "@bazel_skylib//lib:unittest",
    ],
)

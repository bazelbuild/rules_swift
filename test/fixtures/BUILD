load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

bzl_library(
    name = "starlark_tests_bzls",
    srcs = glob(["*.bzl"]),
    visibility = [
        "//test:__pkg__",
    ],
)

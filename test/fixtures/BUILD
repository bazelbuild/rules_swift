load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

bzl_library(
    name = "starlark_tests_bzls",
    srcs = glob(["*.bzl"]),
    visibility = ["//test:__pkg__"],
)

bzl_library(
    name = "common",
    srcs = ["common.bzl"],
    visibility = ["//test:__pkg__"],
)

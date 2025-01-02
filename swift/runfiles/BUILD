load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@build_bazel_rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")

cc_library(
    name = "rules_cc_runfiles_wrapper",
    srcs = ["runfiles.cc"],
    hdrs = ["runfiles.h"],
    aspect_hints = [
        ":swift_hint",
    ],
    deps = [
        "@bazel_tools//tools/cpp/runfiles",
    ],
)

swift_interop_hint(
    name = "swift_hint",
    module_name = "BazelCxxRunfiles",
)

swift_library(
    name = "runfiles",
    srcs = ["Runfiles.swift"],
    module_name = "BazelRunfiles",
    visibility = ["//visibility:public"],
    deps = [
        ":rules_cc_runfiles_wrapper",
    ],
)

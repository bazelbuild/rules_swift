load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_test.bzl", "cc_test")

licenses(["notice"])

cc_library(
    name = "swift_runner",
    srcs = ["swift_runner.cc"],
    hdrs = ["swift_runner.h"],
    deps = [
        "//third_party/json",
        "//tools/common:bazel_substitutions",
        "//tools/common:color",
        "//tools/common:file_system",
        "//tools/common:path_utils",
        "//tools/common:process",
        "//tools/common:target_triple",
        "//tools/common:temp_file",
        "@com_google_absl//absl/base:nullability",
        "@com_google_absl//absl/container:btree",
        "@com_google_absl//absl/container:flat_hash_map",
        "@com_google_absl//absl/container:flat_hash_set",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings",
        "@com_googlesource_code_re2//:re2",
    ],
)

cc_test(
    name = "swift_runner_test",
    srcs = ["swift_runner_test.cc"],
    deps = [
        ":swift_runner",
        "@com_google_absl//absl/container:flat_hash_map",
    ],
)

cc_binary(
    name = "worker",
    srcs = ["main.cc"],
    visibility = ["//visibility:public"],
    deps = [
        ":swift_runner",
    ],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]),
    visibility = [
        "//tools:__pkg__",
    ],
)

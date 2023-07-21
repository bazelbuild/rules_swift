package(
    default_visibility = [
        "//tools/worker:__pkg__",
    ],
)

licenses(["notice"])

cc_library(
    name = "bazel_substitutions",
    srcs = ["bazel_substitutions.cc"],
    hdrs = ["bazel_substitutions.h"],
    deps = [
        "@com_google_absl//absl/container:flat_hash_map",
        "@com_google_absl//absl/strings",
    ],
)

cc_library(
    name = "color",
    hdrs = ["color.h"],
    deps = [
        "@com_google_absl//absl/strings",
    ],
)

cc_library(
    name = "file_system",
    srcs = ["file_system.cc"],
    hdrs = ["file_system.h"],
    deps = [
        ":path_utils",
        ":status",
        "@com_google_absl//absl/cleanup",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/strings",
    ],
)

cc_library(
    name = "path_utils",
    srcs = ["path_utils.cc"],
    hdrs = ["path_utils.h"],
    deps = ["@com_google_absl//absl/strings"],
)

cc_library(
    name = "process",
    srcs = ["process.cc"],
    hdrs = ["process.h"],
    deps = [
        ":path_utils",
        "@com_google_absl//absl/cleanup",
        "@com_google_absl//absl/container:flat_hash_map",
        "@com_google_absl//absl/strings",
    ],
)

cc_library(
    name = "status",
    srcs = ["status.cc"],
    hdrs = ["status.h"],
    deps = [
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/strings",
        "@com_google_absl//absl/strings:str_format",
    ],
)

cc_library(
    name = "temp_file",
    hdrs = ["temp_file.h"],
    deps = ["@com_google_absl//absl/strings"],
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

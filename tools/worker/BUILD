load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")
load("@build_bazel_apple_support//rules:universal_binary.bzl", "universal_binary")

licenses(["notice"])

# Workaround for the rules_apple integration tests to force the use of a
# "worker" that isn't actually a worker but which simply spawns `swiftc`
# directly, because some of the worker dependencies are too complex to
# properly mock out in the test workspace.
#
# This flag is incompatible with the "worker" strategy for SwiftCompile
# actions because it doesn't actually start a processing loop. It merely
# provides an executable with isolated dependencies that can be more easily
# built.
config_setting(
    name = "no_worker",
    define_values = {
        "RULES_SWIFT_BUILD_DUMMY_WORKER": "1",
    },
)

# Internal hinge for index while building V2 feature
config_setting(
    name = "use_global_index_store",
    values = {
        "features": "swift.use_global_index_store",
    },
)

cc_library(
    name = "compile_with_worker",
    srcs = [
        "compile_with_worker.cc",
        "work_processor.cc",
        "work_processor.h",
    ],
    hdrs = ["compile_with_worker.h"],
    deps = [
        ":swift_runner",
        "//third_party/bazel_protos:worker_protocol_cc_proto",
        "//tools/common:file_system",
        "//tools/common:path_utils",
        "//tools/common:temp_file",
        "@com_google_protobuf//:protobuf",
    ],
)

cc_library(
    name = "compile_without_worker",
    srcs = ["compile_without_worker.cc"],
    hdrs = ["compile_without_worker.h"],
    deps = [
        ":swift_runner",
    ],
)

cc_library(
    name = "swift_runner",
    srcs = [
        "output_file_map.cc",
        "output_file_map.h",
        "swift_runner.cc",
    ],
    hdrs = ["swift_runner.h"],
    copts = select({
        ":use_global_index_store": [
            "-DINDEX_IMPORT_PATH=\\\"$(rootpath @build_bazel_rules_swift_index_import//:index_import)\\\"",
        ],
        "//conditions:default": [],
    }),
    data = select({
        ":use_global_index_store": [
            "@build_bazel_rules_swift_index_import//:index_import",
        ],
        "//conditions:default": [],
    }),
    deps = [
        "//tools/common:bazel_substitutions",
        "//tools/common:file_system",
        "//tools/common:process",
        "//tools/common:temp_file",
        "@com_github_nlohmann_json//:json",
    ],
)

cc_binary(
    name = "worker",
    srcs = select({
        ":no_worker": ["no_worker_main.cc"],
        "//conditions:default": ["worker_main.cc"],
    }),
    visibility = ["//visibility:public"],
    deps = select({
        ":no_worker": [":compile_without_worker"],
        "//conditions:default": [
            ":compile_without_worker",
            ":compile_with_worker",
        ],
    }),
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
    testonly = 1,
    srcs = glob(["**"]),
    visibility = [
        "//tools:__pkg__",
    ],
)

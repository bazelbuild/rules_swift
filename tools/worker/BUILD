load("@apple_support//rules:universal_binary.bzl", "universal_binary")
load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

licenses(["notice"])

cc_library(
    name = "compile_with_worker",
    srcs = [
        "compile_with_worker.cc",
        "work_processor.cc",
        "work_processor.h",
    ],
    hdrs = ["compile_with_worker.h"],
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
    deps = [
        ":swift_runner",
        ":worker_protocol",
        "//tools/common:file_system",
        "//tools/common:temp_file",
    ],
)

cc_library(
    name = "compile_without_worker",
    srcs = ["compile_without_worker.cc"],
    hdrs = ["compile_without_worker.h"],
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
    deps = [
        ":swift_runner",
    ],
)

cc_library(
    name = "hermetic_symlink",
    srcs = ["hermetic_symlink.cc"],
    hdrs = ["hermetic_symlink.h"],
    copts = select({
        "//tools:clang-cl": [
            "-Xclang=-fno-split-cold-code",
            "/std=c++17",
        ],
        "//tools:msvc": [
            "/std=c++17",
        ],
        "//conditions:default": [
            "-std=c++17",
        ],
    }),
)

cc_library(
    name = "pcm_hermetic_runner",
    srcs = ["pcm_hermetic_runner.cc"],
    hdrs = ["pcm_hermetic_runner.h"],
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
    deps = [
        ":hermetic_symlink",
        "//tools/common:process",
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
        "@apple_support//configs:apple": [
            "@rules_swift_index_import_5_8//:index_import",
            "@rules_swift_index_import_6_1//:index_import",
        ],
        "//conditions:default": [],
    }),
    deps = [
        ":hermetic_symlink",
        ":pcm_hermetic_runner",
        "//tools/common:bazel_substitutions",
        "//tools/common:color",
        "//tools/common:file_system",
        "//tools/common:path_utils",
        "//tools/common:process",
        "//tools/common:target_triple",
        "//tools/common:temp_file",
        "@abseil-cpp//absl/container:btree",
        "@abseil-cpp//absl/container:flat_hash_map",
        "@abseil-cpp//absl/container:flat_hash_set",
        "@abseil-cpp//absl/strings",
        "@nlohmann_json//:json",
    ],
)

cc_library(
    name = "worker_protocol",
    # worker_protocol.pb.{h,cc} are checked-in generated code so that
    # building the worker does not require a protoc toolchain. To
    # regenerate (required when the `protobuf` dep in MODULE.bazel moves to
    # an incompatible version):
    #   protoc --cpp_out=tools/worker --proto_path=tools/worker \
    #       tools/worker/worker_protocol.proto
    # using a protoc release that matches the MODULE.bazel protobuf version.
    # worker_protocol.proto is a verbatim copy of Bazel's
    # src/main/protobuf/worker_protocol.proto.
    srcs = [
        "worker_protocol.cc",
        "worker_protocol.pb.cc",
    ],
    hdrs = [
        "worker_protocol.h",
        "worker_protocol.pb.h",
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
    deps = [
        "@nlohmann_json//:json",
        "@protobuf//:protobuf",
    ],
)

cc_binary(
    name = "worker",
    srcs = ["worker_main.cc"],
    visibility = ["//visibility:public"],
    deps = [
        ":compile_with_worker",
        ":compile_without_worker",
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

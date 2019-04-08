licenses(["notice"])

cc_library(
    name = "work_processor",
    srcs = [
        "output_file_map.cc",
        "output_file_map.h",
        "work_processor.cc",
    ],
    hdrs = ["work_processor.h"],
    deps = [
        "//third_party/bazel_protos:worker_protocol_cc_proto",
        "//tools/common:file_system",
        "//tools/common:path_utils",
        "//tools/common:process",
        "//tools/common:string_utils",
        "//tools/common:temp_file",
        "@com_github_nlohmann_json//:json",
        "@com_google_protobuf//:protobuf",
    ],
)

cc_binary(
    name = "worker",
    srcs = ["main.cc"],
    visibility = ["//visibility:public"],
    deps = [
        ":work_processor",
        "//third_party/bazel_protos:worker_protocol_cc_proto",
        "@com_google_protobuf//:protobuf",
    ],
)

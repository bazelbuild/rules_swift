licenses(["notice"])

# Workaround for the rules_apple integration tests to completely remove the
# persistent worker from the toolchain, because some of its dependencies are
# too complex to properly mock out in the test workspace.
#
# Note that the dummy worker does not actually *do* anything (it's a no-op
# executable), so using this flag is incompatible with the "worker" strategy
# for SwiftCompile actions. It's merely used to provide a dependency-free
# executable that can be easily built.
config_setting(
    name = "use_dummy",
    define_values = {
        "RULES_SWIFT_BUILD_DUMMY_WORKER": "1",
    },
)

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

WORKER_DEPS = [
    ":work_processor",
    "//third_party/bazel_protos:worker_protocol_cc_proto",
    "@com_google_protobuf//:protobuf",
]

cc_binary(
    name = "worker",
    srcs = select({
        ":use_dummy": ["dummy_main.cc"],
        "//conditions:default": ["main.cc"],
    }),
    visibility = ["//visibility:public"],
    deps = select({
        ":use_dummy": [],
        "//conditions:default": WORKER_DEPS,
    }),
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

load(
    "@rules_proto//proto:defs.bzl",
    "proto_library",
)

proto_library(
    name = "package_2_proto",
    srcs = glob(["*.proto"]),
    visibility = ["//visibility:public"],
    deps = ["//examples/xplatform/proto_library_group/package_1:package_1_proto"],
)

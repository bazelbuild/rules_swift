load("//swift/proto:swift_proto_library.bzl", "swift_proto_library")

proto_library(
    name = "service_messages_proto",
    srcs = ["service_messages.proto"],
    visibility = ["//visibility:public"],
    deps = [
        "@com_google_protobuf//:any_proto",
    ],
)

swift_proto_library(
    name = "service_messages_swift_proto",
    module_name = "ServiceMessages",
    protos = [":service_messages_proto"],
    visibility = ["//visibility:public"],
)

load("@rules_proto//proto:defs.bzl", "proto_library")
load("//swift:swift.bzl", swift_proto_library = "new_swift_proto_library")

proto_library(
    name = "service_proto",
    srcs = ["service.proto"],
    deps = ["//examples/xplatform/grpc/service/service_messages:service_messages_proto"],
)

swift_proto_library(
    name = "service_server_swift_proto",
    compilers = ["//swift/proto/compilers:swift_server_grpc"],
    module_name = "ServiceServer",
    protos = [":service_proto"],
    visibility = ["//visibility:public"],
    deps = ["//examples/xplatform/grpc/service/service_messages:service_messages_swift_proto"],
)

swift_proto_library(
    name = "service_client_swift_proto",
    compilers = ["//swift/proto/compilers:swift_client_grpc"],
    module_name = "ServiceClient",
    protos = [":service_proto"],
    visibility = ["//visibility:public"],
    deps = ["//examples/xplatform/grpc/service/service_messages:service_messages_swift_proto"],
)

swift_proto_library(
    name = "service_test_client_swift_proto",
    additional_plugin_options = {
        "ExtraModuleImports": "ServiceClient",
    },
    compiler_deps = [
        "//examples/xplatform/grpc/service:service_client_swift_proto",
    ],
    compilers = ["//swift/proto/compilers:swift_test_client_grpc"],
    module_name = "ServiceTestClient",
    protos = [":service_proto"],
    visibility = ["//visibility:public"],
    deps = [
        "//examples/xplatform/grpc/service/service_messages:service_messages_swift_proto",
    ],
)

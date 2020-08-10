# This example illustrates how to use `swift_grpc_library` along with
# `swift_proto_library` to build Swift binaries for a gRPC server and
# client.
#
# To explore this example:
#
# 1.  Build both the `:echo_server` and `:echo_client` targets in this package.
# 2.  Run the `echo_server` binary in the background of a terminal. It should
#     print a message indicating that the service has started.
# 3.  Run the `echo_client` binary in the same terminal. It will send a request
#     to this service and then print the response that it received.

load("@rules_proto//proto:defs.bzl", "proto_library")
load(
    "//swift:swift.bzl",
    "swift_binary",
    "swift_grpc_library",
    "swift_proto_library",
    "swift_test",
)

licenses(["notice"])

proto_library(
    name = "echo_proto",
    srcs = ["echo.proto"],
    deps = [
        "@com_google_protobuf//:any_proto",
    ],
)

swift_proto_library(
    name = "echo_proto_swift",
    deps = [":echo_proto"],
)

swift_grpc_library(
    name = "echo_client_services_swift",
    srcs = [":echo_proto"],
    flavor = "client",
    deps = [":echo_proto_swift"],
)

swift_grpc_library(
    name = "echo_client_test_stubs_swift",
    srcs = [":echo_proto"],
    flavor = "client_stubs",
    deps = [":echo_client_services_swift"],
)

swift_grpc_library(
    name = "echo_server_services_swift",
    srcs = [":echo_proto"],
    flavor = "server",
    deps = [":echo_proto_swift"],
)

swift_binary(
    name = "echo_server",
    srcs = ["server_main.swift"],
    deps = [":echo_server_services_swift"],
)

swift_test(
    name = "echo_client_unit_test",
    srcs = ["client_unit_test.swift"],
    deps = [
        ":echo_client_services_swift",
        ":echo_client_test_stubs_swift",
    ],
)

swift_binary(
    name = "echo_client",
    srcs = ["client_main.swift"],
    deps = [":echo_client_services_swift"],
)

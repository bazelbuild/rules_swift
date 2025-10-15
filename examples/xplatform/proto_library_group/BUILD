load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_test.bzl", "swift_test")

swift_binary(
    name = "echo_server",
    srcs = ["server_main.swift"],
    deps = [
        "//examples/xplatform/proto_library_group/service:service_server_swift_proto",
        "@com_github_apple_swift_nio//:NIO",
        "@com_github_apple_swift_nio//:NIOCore",
    ],
)

swift_binary(
    name = "echo_client",
    srcs = ["client_main.swift"],
    deps = [
        "//examples/xplatform/proto_library_group/service:service_client_swift_proto",
        "@com_github_apple_swift_nio//:NIO",
        "@com_github_apple_swift_nio//:NIOCore",
    ],
)

swift_test(
    name = "echo_client_unit_test",
    srcs = [
        "client_unit_test.swift",
    ],
    deps = [
        "//examples/xplatform/proto_library_group/service:service_client_swift_proto",
        "//examples/xplatform/proto_library_group/service:service_server_swift_proto",
        "@com_github_apple_swift_nio//:NIO",
        "@com_github_apple_swift_nio//:NIOCore",
    ],
)

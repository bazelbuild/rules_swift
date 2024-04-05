load(
    "//swift:swift.bzl",
    "swift_binary",
    "swift_test",
)

swift_binary(
    name = "echo_server",
    srcs = ["server_main.swift"],
    deps = [
        "//examples/xplatform/proto_library_group/service:service_server_swift_proto",
    ],
)

swift_binary(
    name = "echo_client",
    srcs = ["client_main.swift"],
    deps = [
        "//examples/xplatform/proto_library_group/service:service_client_swift_proto",
    ],
)

swift_test(
    name = "echo_client_unit_test",
    srcs = [
        "client_unit_test.swift",
        "main.swift",
    ],
    deps = [
        "//examples/xplatform/proto_library_group/service:service_client_swift_proto",
        "//examples/xplatform/proto_library_group/service:service_server_swift_proto",
    ],
)

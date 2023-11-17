load("//swift:swift.bzl", "swift_binary", "swift_test")

licenses(["notice"])

swift_binary(
    name = "hello_world",
    srcs = ["main.swift"],
    module_name = "HelloWorld",
)

swift_test(
    name = "hello_world_test",
    srcs = ["main_test.swift"],
    deps = [":hello_world"],
)

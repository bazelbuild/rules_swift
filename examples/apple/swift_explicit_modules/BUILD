load("//swift:swift.bzl", "swift_binary", "swift_c_module")

swift_c_module(
    name = "shims",
    module_name = "SwiftShims",
    system_module_map = "__BAZEL_XCODE_SDKROOT__/usr/lib/swift/shims/module.modulemap",
)

swift_binary(
    name = "hello_world",
    srcs = ["helloworld.swift"],
    deps = [":shims"],
)

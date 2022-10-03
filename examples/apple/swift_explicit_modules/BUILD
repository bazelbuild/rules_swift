load("//swift:swift.bzl", "swift_binary", "swift_c_module")

# This package is meant to demonstrate the use of explicit clang module compilation.

# In order to build with features "swift.use_c_modules" and "swift.emit_c_module", it is necessary
# to add all of the framework dependencies explicitly. SwiftShims is the only one required for
# compiling a swift binary with no imports.
swift_c_module(
    name = "shims",
    module_name = "SwiftShims",
    system_module_map = "__BAZEL_XCODE_SDKROOT__/usr/lib/swift/shims/module.modulemap",
)

swift_binary(
    name = "hello_world",
    srcs = ["main.swift"],
    deps = [":shims"],
)

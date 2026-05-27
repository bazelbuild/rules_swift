load("//swift/internal:foo.bzl", "apple_sdk_clang_module")
load(
    "//swift/toolchains:xcode_swift_toolchain.bzl",
    "xcode_swift_toolchain",
)

# default_applicable_licenses
package(
    default_visibility = ["//visibility:public"],
)

licenses(["notice"])

exports_files(["LICENSE"])

# Consumed by Bazel integration tests (such as those defined in rules_apple).
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = [
        "//swift:for_bazel_tests",
        "//tools:for_bazel_tests",
    ],
)

apple_sdk_clang_module(
    name = "foo",
    module_name = "_AvailabilityInternal",
    system_module_map = "__BAZEL_XCODE_SDKROOT__/usr/include/DarwinFoundation1.modulemap",
)

xcode_swift_toolchain(
    name = "toolchain",
)

toolchain(
    name = "tc",
    toolchain = ":toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

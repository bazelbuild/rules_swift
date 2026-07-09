load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load(
    "//swift/toolchains:swift_toolchain.bzl",
    "swift_toolchain",
)

platform(
    name = "linux_musl_x86_64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        "//swift/toolchains:static_linux",
    ],
)

swift_toolchain(
    name = "_toolchain_macos_arm64_with_sdkroot",
    arch = "arm64",
    os = "macos",
    parsed_version = "6.3",
    root = ".",
    sdkroot = "testpath",
    version_file = ".swift_version",
)

toolchain(
    name = "toolchain_macos_arm64_with_sdkroot",
    toolchain = ":_toolchain_macos_arm64_with_sdkroot",
    toolchain_type = "//toolchains:toolchain_type",
)

cc_binary(
    name = "static_linux_cc_uses_libcxx",
    srcs = ["static_linux_cc_uses_libcxx.cc"],
    tags = ["manual"],
    visibility = ["//test:__pkg__"],
)

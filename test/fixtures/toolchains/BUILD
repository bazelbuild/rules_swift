load("@rules_cc//cc/toolchains:feature.bzl", "cc_feature")
load("@rules_cc//cc/toolchains/args:sysroot.bzl", "cc_sysroot")
load(
    "//swift/toolchains:swift_toolchain.bzl",
    "swift_toolchain",
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

cc_sysroot(
    name = "other_linux_sysroot_args",
    actions = [
        "@rules_cc//cc/toolchains/actions:compile_actions",
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    sysroot = "@swift_ubuntu22.04_arm64_sysroot//:root",
)

cc_feature(
    name = "other_linux_sysroot_feature",
    args = [":other_linux_sysroot_args"],
    feature_name = "sysroot",
    visibility = ["//test:__subpackages__"],
)

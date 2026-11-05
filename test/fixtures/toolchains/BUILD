load("@bazel_skylib//rules/directory:directory.bzl", "directory")
load("@rules_cc//cc/toolchains:feature.bzl", "cc_feature")
load("@rules_cc//cc/toolchains/args:sysroot.bzl", "cc_sysroot")
load(
    "//swift/toolchains:swift_toolchain.bzl",
    "swift_toolchain",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS", "forward_swift_toolchain_info")

exports_files(["fake_swift_driver.sh"])

swift_toolchain(
    name = "_toolchain_macos_arm64_with_sdkroot",
    arch = "arm64",
    os = "macos",
    parsed_version = "6.3",
    root = ".",
    sdkroot = "testpath",
    version_file = ".swift_version",
    visibility = ["//test:__subpackages__"],
)

toolchain(
    name = "toolchain_macos_arm64_with_sdkroot",
    toolchain = ":_toolchain_macos_arm64_with_sdkroot",
    toolchain_type = "//toolchains:toolchain_type",
)

swift_toolchain(
    name = "toolchain_with_custom_driver",
    arch = "arm64",
    os = "macos",
    parsed_version = "6.3",
    root = ".",
    sdkroot = "testpath",
    swift_executable = ":fake_swift_driver.sh",
    tags = FIXTURE_TAGS,
    version_file = ".swift_version",
    visibility = ["//test:__subpackages__"],
)

forward_swift_toolchain_info(
    name = "resolved_swift_toolchain",
    tags = FIXTURE_TAGS,
    visibility = ["//test:__subpackages__"],
)

directory(
    name = "other_linux_sysroot",
    srcs = [],
)

cc_sysroot(
    name = "other_linux_sysroot_args",
    actions = [
        "@rules_cc//cc/toolchains/actions:compile_actions",
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    sysroot = ":other_linux_sysroot",
)

cc_feature(
    name = "other_linux_sysroot_feature",
    args = [":other_linux_sysroot_args"],
    feature_name = "sysroot",
    visibility = ["//test:__subpackages__"],
)

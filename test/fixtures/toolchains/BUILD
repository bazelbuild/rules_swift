load(
    "//swift/toolchains:swift_toolchain.bzl",
    "swift_toolchain",
)

swift_toolchain(
    name = "_toolchain_macos_arm64_with_sdkroot",
    arch = "arm64",
    os = "macos",
    root = ".",
    sdkroot = "testpath",
    version_file = ".swift_version",
)

toolchain(
    name = "toolchain_macos_arm64_with_sdkroot",
    toolchain = ":_toolchain_macos_arm64_with_sdkroot",
    toolchain_type = "//toolchains:toolchain_type",
)

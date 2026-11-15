load("//swift:swift_toolchain_tool.bzl", "swift_toolchain_tool")
load("//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":swift_multitool_info.bzl", "swift_multitool_info")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

# A stand-in driver for `--@rules_swift//swift:default_swift_executable` and the
# `swift_executable` of the toolchains below.
exports_files(["bin/swift"])

###############################################################################
# Fixtures for testing `swift_toolchain_tool`.

swift_toolchain_tool(
    name = "swift",
    tags = FIXTURE_TAGS,
)

swift_toolchain_tool(
    name = "swift_format",
    tags = FIXTURE_TAGS,
    tool = "swift-format",
)

# Exposes the resolved toolchain's `SwiftToolchainInfo.swift_multitool`.
swift_multitool_info(
    name = "multitool_info",
    tags = FIXTURE_TAGS,
)

###############################################################################
# Toolchains with fixed `swift_multitool` values, selected by the tests with
# `--extra_toolchains` so that the expectations do not depend on the host.

_TEST_ENV = {
    "FOO": "bar baz",
    # A placeholder that only the worker can fill in.
    "SDKROOT": "__BAZEL_XCODE_SDKROOT__",
    "TOOLCHAINS": "com.example.swift",
}

# Runs a custom driver `File` with `--driver-mode=swift` when the tests set
# `--@rules_swift//swift:default_swift_executable`. (The `swift_executable`
# attribute is not used because `get_swift_executable_for_toolchain` returns it
# as a `Target`, not a `File`.)
swift_toolchain(
    name = "_file_driver_toolchain",
    arch = "arm64",
    env = _TEST_ENV,
    os = "macos",
    parsed_version = "6.3",
    root = ".",
    sdkroot = "testpath",
    tags = FIXTURE_TAGS,
    version_file = ".swift_version",
)

toolchain(
    name = "file_driver_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_file_driver_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

# Runs `swift` from a toolchain found on the system, by path.
swift_toolchain(
    name = "_string_driver_toolchain",
    arch = "arm64",
    env = _TEST_ENV,
    os = "macos",
    parsed_version = "6.3",
    root = "/opt/swift/usr",
    sdkroot = "testpath",
    tags = FIXTURE_TAGS,
    version_file = ".swift_version",
)

toolchain(
    name = "string_driver_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_string_driver_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

load("//swift:swift_toolchain_tool.bzl", "swift_toolchain_tool")
load("//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("//swift/toolchains:swift_tools.bzl", "swift_tools")
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

# Fails analysis: `tool` must be a bare name, not a path.
swift_toolchain_tool(
    name = "invalid_tool",
    tags = FIXTURE_TAGS,
    tool = "a/b",
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
# `--@rules_swift//swift:default_swift_executable`.
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

# Runs a custom driver `File` with `--driver-mode=swift`, set with the
# `swift_executable` attribute.
swift_toolchain(
    name = "_attr_file_driver_toolchain",
    arch = "arm64",
    env = _TEST_ENV,
    os = "macos",
    parsed_version = "6.3",
    root = "/opt/swift/usr",
    sdkroot = "testpath",
    swift_executable = ":bin/swift",
    tags = FIXTURE_TAGS,
    version_file = ".swift_version",
)

toolchain(
    name = "attr_file_driver_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_attr_file_driver_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

# A toolchain found on the system with a relative root, which is not valid
# under `bazel run`, so `swift` is found on `PATH`.
swift_toolchain(
    name = "_relative_root_toolchain",
    arch = "arm64",
    env = _TEST_ENV,
    os = "macos",
    parsed_version = "6.3",
    root = "relative/usr",
    sdkroot = "testpath",
    tags = FIXTURE_TAGS,
    version_file = ".swift_version",
)

toolchain(
    name = "relative_root_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_relative_root_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

# A hermetic toolchain that provides a `swift` multi-tool and the files that it
# needs at runtime.
swift_tools(
    name = "_hermetic_swift_tools",
    additional_inputs = [],
    swift = ":hermetic/usr/bin/swift",
    swift_autolink_extract = ":hermetic/usr/bin/swiftc",
    swift_driver = ":hermetic/usr/bin/swiftc",
    swift_runfiles = [":hermetic/usr/bin/swift-package"],
    swift_symbolgraph_extract = ":hermetic/usr/bin/swiftc",
    tags = FIXTURE_TAGS,
)

swift_toolchain(
    name = "_hermetic_swift_toolchain",
    arch = "arm64",
    env = _TEST_ENV,
    os = "macos",
    parsed_version = "6.3",
    sdkroot = "testpath",
    swift_tools = ":_hermetic_swift_tools",
    tags = FIXTURE_TAGS,
    version_file = ".swift_version",
)

toolchain(
    name = "hermetic_swift_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_hermetic_swift_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

# A hermetic toolchain without a `swift` multi-tool, so its `swiftc` driver is
# run with `--driver-mode=swift`.
swift_tools(
    name = "_hermetic_driver_only_swift_tools",
    additional_inputs = [],
    swift_autolink_extract = ":hermetic/usr/bin/swiftc",
    swift_driver = ":hermetic/usr/bin/swiftc",
    swift_symbolgraph_extract = ":hermetic/usr/bin/swiftc",
    tags = FIXTURE_TAGS,
)

swift_toolchain(
    name = "_hermetic_driver_only_toolchain",
    arch = "arm64",
    env = _TEST_ENV,
    os = "macos",
    parsed_version = "6.3",
    sdkroot = "testpath",
    swift_tools = ":_hermetic_driver_only_swift_tools",
    tags = FIXTURE_TAGS,
    version_file = ".swift_version",
)

toolchain(
    name = "hermetic_driver_only_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_hermetic_driver_only_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

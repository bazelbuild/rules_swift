load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("//swift:swift_toolchain_tool.bzl", "swift_toolchain_tool")
load("//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("//swift/toolchains:swift_tools.bzl", "swift_tools")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":fake_cc_toolchain_config.bzl", "fake_cc_toolchain_config")
load(":swift_multitool_info.bzl", "swift_multitool_info")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

# Stand-in drivers for `--@rules_swift//swift:default_swift_executable` and the
# `swift_executable` of the toolchains below. `bin/fake_swift.bat` is the
# Windows one that `//test/swift_toolchain_tool` runs.
exports_files([
    "bin/fake_swift.bat",
    "bin/swift",
])

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

###############################################################################
# Fixed target platforms and the C++ toolchains that `swift_toolchain` needs
# for them. The C++ toolchains only satisfy toolchain resolution; they cannot
# compile or link anything. The tests that check the bash script target
# `linux_x86_64` so that they do not depend on the host, which would get a
# `.bat` file on Windows.

filegroup(
    name = "_empty",
    srcs = [],
    tags = FIXTURE_TAGS,
)

platform(
    name = "linux_x86_64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    tags = FIXTURE_TAGS,
)

fake_cc_toolchain_config(
    name = "_linux_cc_toolchain_config",
    compiler = "clang",
    tags = FIXTURE_TAGS,
    target_cpu = "k8",
    target_system_name = "x86_64-unknown-linux-gnu",
)

cc_toolchain(
    name = "_linux_cc_toolchain",
    all_files = ":_empty",
    compiler_files = ":_empty",
    dwp_files = ":_empty",
    linker_files = ":_empty",
    objcopy_files = ":_empty",
    strip_files = ":_empty",
    tags = FIXTURE_TAGS,
    toolchain_config = ":_linux_cc_toolchain_config",
)

toolchain(
    name = "linux_cc_toolchain",
    tags = FIXTURE_TAGS,
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    toolchain = ":_linux_cc_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

platform(
    name = "windows_x86_64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:windows",
    ],
    tags = FIXTURE_TAGS,
)

fake_cc_toolchain_config(
    name = "_windows_cc_toolchain_config",
    compiler = "msvc-cl",
    tags = FIXTURE_TAGS,
    target_cpu = "x64_windows",
    target_system_name = "x86_64-unknown-windows-msvc",
)

cc_toolchain(
    name = "_windows_cc_toolchain",
    all_files = ":_empty",
    compiler_files = ":_empty",
    dwp_files = ":_empty",
    linker_files = ":_empty",
    objcopy_files = ":_empty",
    strip_files = ":_empty",
    tags = FIXTURE_TAGS,
    toolchain_config = ":_windows_cc_toolchain_config",
)

toolchain(
    name = "windows_cc_toolchain",
    tags = FIXTURE_TAGS,
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:windows",
    ],
    toolchain = ":_windows_cc_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

###############################################################################
# Windows fixtures. The tests target `windows_x86_64` so that the rule writes a
# `.bat` file, and select one of the toolchains below with `--extra_toolchains`.

_WINDOWS_TEST_ENV = {
    # `%` must be doubled in a batch file.
    "FOO": "100% done",
    "Path": "C:\\Swift\\usr\\bin;C:\\Windows",
    "ProgramData": "C:\\ProgramData",
    # A placeholder that only the worker can fill in.
    "SDKROOT": "__BAZEL_XCODE_SDKROOT__",
}

# An autoconfigured-style Windows toolchain: an absolute root and `.exe` tools.
swift_toolchain(
    name = "_windows_string_driver_toolchain",
    arch = "x86_64",
    env = _WINDOWS_TEST_ENV,
    os = "windows",
    parsed_version = "6.3",
    root = "C:/Swift/usr",
    sdkroot = "C:/Swift/Platforms/Windows.platform/Developer/SDKs/Windows.sdk",
    tags = FIXTURE_TAGS,
    tool_executable_suffix = ".exe",
    version_file = ".swift_version",
    xctest_version = "development",
)

toolchain(
    name = "windows_string_driver_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_windows_string_driver_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

# The same toolchain with a custom driver `File`.
swift_toolchain(
    name = "_windows_file_driver_toolchain",
    arch = "x86_64",
    env = _WINDOWS_TEST_ENV,
    os = "windows",
    parsed_version = "6.3",
    root = "C:/Swift/usr",
    sdkroot = "C:/Swift/Platforms/Windows.platform/Developer/SDKs/Windows.sdk",
    swift_executable = ":bin/swift",
    tags = FIXTURE_TAGS,
    tool_executable_suffix = ".exe",
    version_file = ".swift_version",
    xctest_version = "development",
)

toolchain(
    name = "windows_file_driver_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_windows_file_driver_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

# Fails analysis: a double quote cannot be escaped in a `.bat` file.
swift_toolchain(
    name = "_windows_quoted_env_toolchain",
    arch = "x86_64",
    env = _WINDOWS_TEST_ENV | {"FOO": 'say "hi"'},
    os = "windows",
    parsed_version = "6.3",
    root = "C:/Swift/usr",
    sdkroot = "C:/Swift/Platforms/Windows.platform/Developer/SDKs/Windows.sdk",
    tags = FIXTURE_TAGS,
    tool_executable_suffix = ".exe",
    version_file = ".swift_version",
    xctest_version = "development",
)

toolchain(
    name = "windows_quoted_env_toolchain",
    tags = FIXTURE_TAGS,
    toolchain = ":_windows_quoted_env_toolchain",
    toolchain_type = "//toolchains:toolchain_type",
)

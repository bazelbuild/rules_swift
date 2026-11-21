load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift_toolchain_tool.bzl", "swift_toolchain_tool")
load("//test:transitions.bzl", "transition_test")

licenses(["notice"])

swift_toolchain_tool(
    name = "swift",
    tool = "swift",
)

swift_toolchain_tool(
    name = "swift_format",
    tool = "swift-format",
)

# Runs the wrapper as a tool of an action rather than with `bazel run`. On
# Windows, `cmd_bat` runs the `.bat` wrapper under cmd.exe, which gets the
# paths with backslashes.
genrule(
    name = "swift_version_genrule",
    outs = ["swift_version.txt"],
    cmd = "$(location :swift) --version > $@ 2>&1",
    cmd_bat = "$(location :swift) --version > $@ 2>&1",
    tools = [":swift"],
)

# Arguments of `run_tool_test.sh`: the tool's runfiles path, a regex that its
# output must match, and the arguments to run it with; or `--output`, a file's
# runfiles path, and a regex that its contents must match.
_RUN_TESTS = {
    # Runs the toolchain's `swift` driver.
    "swift_version_test": [
        "_main/test/swift_toolchain_tool/swift",
        "'Swift version [0-9]+'",
        "--version",
    ],
    # Runs a subcommand that the driver dispatches to `swift-package`.
    "swift_package_version_test": [
        "_main/test/swift_toolchain_tool/swift",
        "'Swift Package Manager'",
        "package",
        "--version",
    ],
    # Runs a sibling of the driver rather than the driver itself. Release
    # toolchains print a version; swift.org builds of `swift-format` print
    # `main`.
    # Checks the output of the genrule above.
    "swift_version_genrule_test": [
        "--output",
        "_main/test/swift_toolchain_tool/swift_version.txt",
        "'Swift version [0-9]+'",
    ],
    "swift_format_version_test": [
        "_main/test/swift_toolchain_tool/swift_format",
        "'^([0-9]+[.][0-9]+|main)'",
        "--version",
    ],
}

[
    sh_test(
        name = name,
        srcs = ["run_tool_test.sh"],
        args = args,
        data = [
            ":swift",
            ":swift_format",
            ":swift_version_genrule",
        ],
        deps = ["@bazel_tools//tools/bash/runfiles"],
    )
    for name, args in _RUN_TESTS.items()
]

# The hermetic toolchain is resolved first on Linux CI, so these wrappers
# select the autoconfigured host toolchain to cover it. Keep them manual so
# that hermetic //... builds do not select a host toolchain.
[
    transition_test(
        name = "linux_non_hermetic_{}".format(name),
        args = args,
        extra_toolchains = [
            "//swift/toolchains:linux-swift-toolchain_aarch64",
            "//swift/toolchains:linux-swift-toolchain_x86_64",
        ],
        tags = ["manual"],
        target = ":{}".format(name),
        target_compatible_with = ["@platforms//os:linux"],
    )
    for name, args in _RUN_TESTS.items()
]

# Runs the `.bat` wrapper with a custom driver `File` that is itself a `.bat`,
# found through the runfiles, and checks that it gets `--driver-mode=swift`.
_FAKE_DRIVER_ARGS = [
    "_main/test/swift_toolchain_tool/swift",
    "'fake.*--driver-mode=swift'",
    "--version",
]

sh_test(
    name = "_fake_driver_version_test",
    srcs = ["run_tool_test.sh"],
    args = _FAKE_DRIVER_ARGS,
    data = [":swift"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:windows"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

transition_test(
    name = "windows_fake_driver_version_test",
    args = _FAKE_DRIVER_ARGS,
    default_swift_executable = "//test/fixtures/swift_toolchain_tool:bin/fake_swift.bat",
    target = ":_fake_driver_version_test",
    target_compatible_with = ["@platforms//os:windows"],
)

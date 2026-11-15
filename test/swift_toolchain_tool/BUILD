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

# Arguments of `run_tool_test.sh`: the tool's runfiles path, a regex that its
# output must match, and the arguments to run it with.
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

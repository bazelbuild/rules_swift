"""Tests for swift toolchain."""

load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

toolchain_macos_arm64_with_sdkroot_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:extra_toolchains": ["//test/fixtures/toolchains:toolchain_macos_arm64_with_sdkroot"],
    },
)

toolchain_static_linux_x86_64_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:platforms": [
            str(Label("//test/fixtures/toolchains:linux_musl_x86_64")),
        ],
    },
)

def swift_toolchain_test_suite(name, tags = []):
    """Test suite for swift_toolchain's provider.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Make sure the -sdk argument is appended
    toolchain_macos_arm64_with_sdkroot_test(
        name = "{}_with_sdkroot".format(name),
        expected_argv = ["-target", "-sdk", "testpath"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/basic:first",
    )

    toolchain_static_linux_x86_64_test(
        name = "{}_static_linux_x86_64".format(name),
        expected_argv = [
            "-target",
            "x86_64-swift-linux-musl",
            "-sdk",
            "swift-linux-musl/musl-1.2.5.sdk/x86_64",
            "-resource-dir",
            "swift-linux-musl/musl-1.2.5.sdk/x86_64/usr/lib/swift_static",
            "-Xcc",
            "--target=x86_64-swift-linux-musl",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/basic:first",
    )

    toolchain_static_linux_x86_64_test(
        name = "{}_static_linux_cc_links_libcxx".format(name),
        expected_argv = [
            "--target=x86_64-swift-linux-musl",
            "--sysroot",
            "swift-linux-musl/musl-1.2.5.sdk/x86_64",
            "-lc++",
        ],
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "//test/fixtures/toolchains:static_linux_cc_uses_libcxx",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

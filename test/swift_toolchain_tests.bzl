"""Tests for swift toolchain."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)

toolchain_macos_arm64_with_sdkroot_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:extra_toolchains": ["//test/fixtures/toolchains:toolchain_macos_arm64_with_sdkroot"],
    },
)

linux_sdk_with_other_cc_sysroot_test = make_action_command_line_test_rule(
    config_settings = {
        str(Label("//swift/toolchains:linux_sysroot_feature")): str(Label("//test/fixtures/toolchains:other_linux_sysroot_feature")),
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

    action_command_line_test(
        name = "{}_linux_sdk_from_cc_sysroot".format(name),
        expected_argv = ["-sdk", "swift_ubuntu22.04_amd64_sysroot"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = [
            "@platforms//cpu:x86_64",
            "@platforms//os:linux",
        ],
        target_under_test = "//test/fixtures/basic:first",
    )

    # The exec Swift toolchain's `sysroot` wins over the C++ toolchain's.
    linux_sdk_with_other_cc_sysroot_test(
        name = "{}_linux_sdk_from_swift_sysroot".format(name),
        expected_argv = ["-sdk", "swift_ubuntu22.04_amd64_sysroot"],
        mnemonic = "SwiftCompile",
        not_expected_argv = ["swift_ubuntu22.04_arm64_sysroot"],
        tags = all_tags,
        target_compatible_with = [
            "@platforms//cpu:x86_64",
            "@platforms//os:linux",
        ],
        target_under_test = "//test/fixtures/basic:first",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

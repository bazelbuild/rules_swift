"""Tests for custom toolchain linker placeholder handling."""

load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

custom_toolchain_linking_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:action_env": [
            "TOOLCHAINS=test.toolchain.id",
        ],
    },
)

def custom_toolchain_linking_test_suite(name, tags = []):
    """Test suite for custom toolchain linker placeholders.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    custom_toolchain_linking_test(
        name = "{}_uses_linker_placeholder".format(name),
        expected_argv = [
            "-L__BAZEL_CUSTOM_XCODE_TOOLCHAIN_PATH__/usr/lib/swift/macosx",
        ],
        mnemonic = "CppLink",
        not_expected_argv = [
            "__BAZEL_SWIFT_TOOLCHAIN_PATH__/usr/lib/swift/macosx",
        ],
        tags = all_tags,
        target_under_test = "//test/fixtures/linking:bin",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

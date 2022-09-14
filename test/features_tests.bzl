"""Tests for various features that aren't large enough to need their own tests file."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

default_test = make_action_command_line_test_rule()

file_prefix_map_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.file_prefix_map",
        ],
    },
)

file_prefix_xcode_remap_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.file_prefix_map",
            "swift.remap_xcode_path",
        ],
    },
)

def features_test_suite(name):
    """Test suite for various features.

    Args:
      name: the base name to be used in things created by this macro
    """
    default_test(
        name = "{}_default_test".format(name),
        tags = [name],
        expected_argv = ["-emit-object"],
        not_expected_argv = [
            "-file-prefix-map",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    file_prefix_map_test(
        name = "{}_file_prefix_map_test".format(name),
        tags = [name],
        expected_argv = [
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    file_prefix_xcode_remap_test(
        name = "{}_file_prefix_xcode_remap_test".format(name),
        tags = [name],
        expected_argv = [
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
            "-file-prefix-map",
            "__BAZEL_XCODE_DEVELOPER_DIR__=DEVELOPER_DIR",
        ],
        target_compatible_with = ["@platforms//os:macos"],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

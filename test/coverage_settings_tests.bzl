"""Tests for coverage-related command line flags under various configs."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

default_coverage_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:collect_code_coverage": "true",
    },
)

coverage_prefix_map_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:collect_code_coverage": "true",
        "//command_line_option:features": [
            "swift.coverage_prefix_map",
        ],
    },
)

coverage_xcode_prefix_map_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:collect_code_coverage": "true",
        "//command_line_option:features": [
            "swift.coverage_prefix_map",
            "swift.remap_xcode_path",
        ],
    },
)

def coverage_settings_test_suite(name = "coverage_settings"):
    """Test suite for coverage options.

    Args:
        name: The name prefix for all the nested tests
    """
    default_coverage_test(
        name = "{}_default_coverage".format(name),
        tags = [name],
        expected_argv = [
            "-profile-generate",
            "-profile-coverage-mapping",
        ],
        not_expected_argv = [
            "-Xwrapped-swift=-coverage-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    coverage_prefix_map_test(
        name = "{}_prefix_map".format(name),
        tags = [name],
        expected_argv = [
            "-profile-generate",
            "-profile-coverage-mapping",
            "-Xwrapped-swift=-coverage-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    coverage_xcode_prefix_map_test(
        name = "{}_xcode_prefix_map".format(name),
        tags = [name],
        expected_argv = [
            "-coverage-prefix-map",
            "__BAZEL_XCODE_DEVELOPER_DIR__=DEVELOPER_DIR",
        ],
        target_compatible_with = [
            "@bazel_tools//platforms:osx",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

"""Tests for `swift.emit_stats`."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)
load(
    "//test/rules:provider_test.bzl",
    "make_provider_test_rule",
)

stats_output_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.emit_stats",
        ],
    },
)

stats_output_provider_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.emit_stats",
        ],
    },
)

def stats_output_test_suite(name, tags = []):
    """Test suite for Swift stats output.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    action_command_line_test(
        name = "{}_disabled_by_default".format(name),
        mnemonic = "SwiftCompile",
        not_expected_argv = [
            "-stats-output-dir",
        ],
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    stats_output_command_line_test(
        name = "{}_command_line".format(name),
        expected_argv = [
            "-Xwrapped-swift=-stats-output-dir=$(BIN_DIR)/test/fixtures/debug_settings/simple.swift-stats",
        ],
        mnemonic = "SwiftCompile",
        not_expected_argv = [
            "-trace-stats-events",
        ],
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    stats_output_provider_test(
        name = "{}_default_files".format(name),
        expected_files = [
            "test/fixtures/debug_settings/simple.swift-stats",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    stats_output_provider_test(
        name = "{}_output_group".format(name),
        expected_files = [
            "test/fixtures/debug_settings/simple.swift-stats",
        ],
        field = "swift_stats",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

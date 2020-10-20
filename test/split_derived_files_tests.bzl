"""Tests for derived files related command line flags under various configs."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "make_provider_test_rule",
)

# Default outputs both .a and .swiftmodule
# Split outputs 2 actions one with .a one with .swiftmodule
# Split WMO works the same as split w/o WMO

default_no_split_test = make_action_command_line_test_rule()

default_no_split_provider_test = make_provider_test_rule()

split_swiftmodule_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

split_swiftmodule_provider_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

split_swiftmodule_wmo_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:swiftcopt": [
            "-whole-module-optimization",
        ],
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

split_swiftmodule_wmo_provider_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:swiftcopt": [
            "-whole-module-optimization",
        ],
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

def split_derived_files_test_suite(name = "split_derived_files"):
    """Test suite for split derived files options.

    Args:
        name: The name prefix for all the nested tests
    """
    default_no_split_test(
        name = "{}_default_no_split_args".format(name),
        expected_argv = [
            "-emit-module-path",
            "-emit-object",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    default_no_split_provider_test(
        name = "{}_default_no_split_provider".format(name),
        expected_files = [
            "test_fixtures_debug_settings_simple.swiftmodule",
        ],
        field = "direct_modules.swift.swiftmodule",
        provider = "SwiftInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    default_no_split_provider_test(
        name = "{}_default_no_split_provider_ccinfo".format(name),
        expected_files = [
            "libsimple.a",
        ],
        field = "linking_context.libraries_to_link.pic_static_library!",
        provider = "CcInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    split_swiftmodule_test(
        name = "{}_object_only".format(name),
        expected_argv = [
            "-emit-object",
        ],
        mnemonic = "SwiftCompile",
        not_expected_argv = [
            "-emit-module-path",
        ],
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    split_swiftmodule_test(
        name = "{}_swiftmodule_only".format(name),
        expected_argv = [
            "-emit-module-path",
        ],
        mnemonic = "SwiftDeriveFiles",
        not_expected_argv = [
            "-emit-object",
        ],
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    split_swiftmodule_provider_test(
        name = "{}_split_provider".format(name),
        expected_files = [
            "test_fixtures_debug_settings_simple.swiftmodule",
        ],
        field = "direct_modules.swift.swiftmodule",
        provider = "SwiftInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    split_swiftmodule_provider_test(
        name = "{}_split_provider_ccinfo".format(name),
        expected_files = [
            "libsimple.a",
        ],
        field = "linking_context.libraries_to_link.pic_static_library!",
        provider = "CcInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    split_swiftmodule_wmo_test(
        name = "{}_object_only_wmo".format(name),
        expected_argv = [
            "-emit-object",
            "-whole-module-optimization",
        ],
        mnemonic = "SwiftCompile",
        not_expected_argv = [
            "-emit-module-path",
        ],
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    split_swiftmodule_wmo_test(
        name = "{}_swiftmodule_only_wmo".format(name),
        expected_argv = [
            "-emit-module-path",
            "-whole-module-optimization",
        ],
        mnemonic = "SwiftDeriveFiles",
        not_expected_argv = [
            "-emit-object",
        ],
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

"""Tests for various compiler arguments."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)

split_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

def compiler_arguments_test_suite(name):
    """Test suite for various command line flags passed to Swift compiles.

    Args:
      name: the base name to be used in things created by this macro
    """

    action_command_line_test(
        name = "{}_no_package_by_default".format(name),
        not_expected_argv = ["-package-name"],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_arguments:no_package_name",
    )

    action_command_line_test(
        name = "{}_lib_with_package".format(name),
        expected_argv = ["-package-name lib"],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_arguments:lib_package_name",
    )

    action_command_line_test(
        name = "{}_bin_with_package".format(name),
        expected_argv = ["-package-name bin"],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_arguments:bin_package_name",
    )

    action_command_line_test(
        name = "{}_test_with_package".format(name),
        expected_argv = ["-package-name test"],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_arguments:test_package_name",
    )

    split_test(
        name = "{}_split_lib_with_package".format(name),
        expected_argv = ["-package-name lib"],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_arguments:lib_package_name",
    )

    split_test(
        name = "{}_split_module_with_package".format(name),
        expected_argv = ["-package-name lib"],
        mnemonic = "SwiftDeriveFiles",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_arguments:lib_package_name",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

"""Tests for validating @main related usage"""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

mainattr_test = make_action_command_line_test_rule()

def mainattr_test_suite(name):
    mainattr_test(
        name = "{}_single_main".format(name),
        not_expected_argv = ["-parse-as-library"],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/mainattr:main",
    )

    mainattr_test(
        name = "{}_single_custom_main".format(name),
        expected_argv = ["-parse-as-library"],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/mainattr:custommain",
    )

    mainattr_test(
        name = "{}_multiple_files".format(name),
        not_expected_argv = ["-parse-as-library"],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/mainattr:multiplefiles",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

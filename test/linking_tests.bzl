"""Tests for validating linking behavior"""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

linking_test = make_action_command_line_test_rule()

def linking_test_suite(name):
    linking_test(
        name = "{}_duplicate_linking_args".format(name),
        expected_argv = [
            "-framework framework1",
            "-framework framework2",
        ],
        mnemonic = "CppLink",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/linking:bin",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

"""Tests for validating linking behavior"""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
)

def imported_framework_test_suite(name):
    action_command_line_test(
        name = "{}_disable_autolink_framework_test".format(name),
        expected_argv = [
            "-Xfrontend -disable-autolink-framework -Xfrontend framework1",
            "-Xfrontend -disable-autolink-framework -Xfrontend framework2",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/linking:bin",
    )

    action_command_line_test(
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

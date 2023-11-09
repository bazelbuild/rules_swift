"""Tests for derived files related command line flags under various configs."""

load(
    "@build_bazel_rules_swift//test/rules:swift_shell_test.bzl",
    "swift_shell_test",
)

def xctest_runner_test_suite(name):
    """Test suite for xctest runner.

    Args:
      name: the base name to be used in things created by this macro
    """
    swift_shell_test(
        name = "{}_pass".format(name),
        expected_return_code = 0,
        expected_logs = [
            "Test Suite 'PassingUnitTests' passed",
            "Test Suite 'PassingUnitTests.xctest' passed",
            "Executed 3 tests, with 0 failures",
        ],
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/xctest_runner:PassingUnitTests",
        target_compatible_with = ["@platforms//os:macos"],
    )

    swift_shell_test(
        name = "{}_fail".format(name),
        expected_return_code = 1,
        expected_logs = [
            "Test Suite 'FailingUnitTests' failed",
            "Test Suite 'FailingUnitTests.xctest' failed",
            "Executed 1 test, with 1 failure",
        ],
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/xctest_runner:FailingUnitTests",
        target_compatible_with = ["@platforms//os:macos"],
    )

    swift_shell_test(
        name = "{}_no_tests".format(name),
        expected_return_code = 1,
        expected_logs = [
            "Executed 0 tests, with 0 failures",
            "error: no tests were executed",
        ],
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/xctest_runner:EmptyUnitTests",
        target_compatible_with = ["@platforms//os:macos"],
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

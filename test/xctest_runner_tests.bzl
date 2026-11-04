"""Tests for derived files related command line flags under various configs."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//test/rules:swift_shell_test.bzl", "swift_shell_test")

_NO_TESTS_DISCOVERED = "ERROR: No tests were discovered"

def xctest_runner_test_suite(name, tags = []):
    """Test suite for xctest runner.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    build_test(
        name = "{}_macos_11_0_build".format(name),
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        targets = ["//test/fixtures/xctest_runner:PassingUnitTests_macos_11_0"],
    )

    swift_shell_test(
        name = "{}_pass".format(name),
        expected_return_code = 0,
        expected_logs = [
            "Test Suite 'PassingUnitTests' passed",
            "Test Suite 'PassingUnitTests.xctest' passed",
            "Executed 3 tests, with 0 failures",
        ],
        not_expected_logs = [_NO_TESTS_DISCOVERED],
        tags = all_tags,
        target_under_test = "//test/fixtures/xctest_runner:PassingUnitTests",
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
        not_expected_logs = [_NO_TESTS_DISCOVERED],
        tags = all_tags,
        target_under_test = "//test/fixtures/xctest_runner:FailingUnitTests",
        target_compatible_with = ["@platforms//os:macos"],
    )

    swift_shell_test(
        name = "{}_no_tests".format(name),
        expected_return_code = 1,
        expected_logs = [
            "Executed 0 tests, with 0 failures",
            _NO_TESTS_DISCOVERED,
        ],
        tags = all_tags,
        target_under_test = "//test/fixtures/xctest_runner:EmptyUnitTests",
        target_compatible_with = ["@platforms//os:macos"],
    )

    swift_shell_test(
        name = "{}_swift_testing_no_tests".format(name),
        expected_return_code = 1,
        expected_logs = [
            "Test run with 0 tests.* passed after",
            _NO_TESTS_DISCOVERED,
        ],
        tags = all_tags,
        target_under_test = "//test/fixtures/xctest_runner:EmptySwiftTestingSuite",
    )

    swift_shell_test(
        name = "{}_swift_testing_pass".format(name),
        expected_return_code = 0,
        expected_logs = [
            "Test run with 1 test.* passed after",
        ],
        not_expected_logs = [_NO_TESTS_DISCOVERED],
        tags = all_tags,
        target_under_test = "//test/fixtures/xctest_runner:PassingSwiftTestingTests",
    )

    swift_shell_test(
        name = "{}_swift_testing_fail".format(name),
        expected_return_code = 1,
        expected_logs = [
            "Test run with 1 test.* failed after",
        ],
        not_expected_logs = [_NO_TESTS_DISCOVERED],
        tags = all_tags,
        target_under_test = "//test/fixtures/xctest_runner:FailingSwiftTestingTests",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

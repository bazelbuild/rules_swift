""" Tests for validating if SwiftCompile actions have the correct flags to developer framework paths """

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

testonly_swift_library_action_command_line_test = make_action_command_line_test_rule()

swift_library_action_command_line_test = make_action_command_line_test_rule()

swift_test_action_command_line_test = make_action_command_line_test_rule()

swift_test_action_linkopts_command_line_test = make_action_command_line_test_rule()

def developer_framework_paths_test_suite(name):
    """Test suite for developer framework paths for test targets or targets marked as `testonly`

    Args:
      name: the base name to be used in things created by this macro
    """

    testonly_swift_library_action_command_line_test(
        name = "{}_testonly_swift_library_build".format(name),
        expected_argv = [
            "-F__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/Library/Frameworks",
            "-I__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/usr/lib",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/developer_framework_paths:simple_testonly",
    )

    swift_library_action_command_line_test(
        name = "{}_swift_library_build".format(name),
        not_expected_argv = [
            "-F__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/Library/Frameworks",
            "-I__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/usr/lib",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/developer_framework_paths:simple",
    )

    swift_test_action_command_line_test(
        name = "{}_swift_test_build".format(name),
        expected_argv = [
            "-F__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/Library/Frameworks",
            "-I__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/usr/lib",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/developer_framework_paths:simple_test",
    )

    swift_test_action_linkopts_command_line_test(
        name = "{}_swift_test_build_linkopts".format(name),
        expected_argv = [
            "-F__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/Library/Frameworks",
            "-I__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/usr/lib",
        ],
        mnemonic = "CppLink",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/developer_framework_paths:simple_test",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

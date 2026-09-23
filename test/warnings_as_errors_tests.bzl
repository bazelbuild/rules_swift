# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Tests for `swift.werror.*` features."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
)

visibility("private")

def warnings_as_errors_test_suite(name, tags = []):
    """Test suite for `swift.werror.*` features.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Legacy diagnostic IDs are unsupported and must not reach the compiler.
    action_command_line_test(
        name = "{}_legacy_diagnostic_id".format(name),
        not_expected_argv = [
            "-Xwrapped-swift=-warning-as-error=access_control_ext_member_more",
            "-Werror",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/warnings_as_errors:legacy_diagnostic_id",
    )

    # Verify that a warning group (starting with uppercase) routes to compiler
    # flag -Werror <group> and not runner scraping.
    action_command_line_test(
        name = "{}_warning_group".format(name),
        expected_argv = [
            "-Werror DeprecatedDeclaration",
        ],
        not_expected_argv = [
            "-Xwrapped-swift=-warning-as-error=DeprecatedDeclaration",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/warnings_as_errors:warning_group",
    )

    # A legacy diagnostic ID must not interfere with a compiler warning group.
    action_command_line_test(
        name = "{}_mixed_diagnostic_and_group".format(name),
        expected_argv = [
            "-Werror DeprecatedDeclaration",
        ],
        not_expected_argv = [
            "-Werror access_control_ext_member_more",
            "-Xwrapped-swift=-warning-as-error=access_control_ext_member_more",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/warnings_as_errors:mixed_diagnostic_and_group",
    )

    # Verify that disabled features emit neither flag.
    action_command_line_test(
        name = "{}_disabled_features".format(name),
        not_expected_argv = [
            "-Werror DeprecatedDeclaration",
            "-Xwrapped-swift=-warning-as-error=access_control_ext_member_more",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/warnings_as_errors:disabled_features",
    )

    action_command_line_test(
        name = "{}_empty_name".format(name),
        not_expected_argv = ["-Werror"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/warnings_as_errors:empty_name",
    )

    for mnemonic in ["SwiftCompile", "SwiftDeriveFiles"]:
        action_command_line_test(
            name = "{}_split_{}".format(name, mnemonic),
            expected_argv = [
                "-Werror DeprecatedDeclaration",
                "-Werror UnusedResult",
            ],
            mnemonic = mnemonic,
            tags = all_tags,
            target_under_test = "//test/fixtures/warnings_as_errors:split_warning_groups",
        )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

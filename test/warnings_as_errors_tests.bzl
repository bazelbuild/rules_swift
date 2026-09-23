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
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
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

    # Verify that a legacy diagnostic ID (starting with lowercase) routes to
    # runner scraping via -Xwrapped-swift=-warning-as-error=<id> and not -Werror.
    action_command_line_test(
        name = "{}_legacy_diagnostic_id".format(name),
        expected_argv = [
            "-debug-diagnostic-names",
            "-Xwrapped-swift=-warning-as-error=access_control_ext_member_more",
        ],
        not_expected_argv = [
            "-Werror access_control_ext_member_more",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/warnings_as_errors:legacy_diagnostic_id",
    )

    # Verify that a warning group (starting with uppercase) routes to compiler
    # flag -Werror <group> and not runner scraping.
    action_command_line_test(
        name = "{}_warning_group".format(name),
        expected_argv = [
            "-debug-diagnostic-names",
            "-Werror DeprecatedDeclaration",
        ],
        not_expected_argv = [
            "-Xwrapped-swift=-warning-as-error=DeprecatedDeclaration",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/warnings_as_errors:warning_group",
    )

    # Verify that both legacy diagnostic IDs and warning groups can be used together.
    action_command_line_test(
        name = "{}_mixed_diagnostic_and_group".format(name),
        expected_argv = [
            "-debug-diagnostic-names",
            "-Werror DeprecatedDeclaration",
            "-Xwrapped-swift=-warning-as-error=access_control_ext_member_more",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/warnings_as_errors:mixed_diagnostic_and_group",
    )

    # Verify that disabled features emit neither flag.
    action_command_line_test(
        name = "{}_disabled_features".format(name),
        not_expected_argv = [
            "-Werror DeprecatedDeclaration",
            "-Xwrapped-swift=-warning-as-error=access_control_ext_member_more",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/warnings_as_errors:disabled_features",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

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

"""Tests for `swift_test`, `swift_binary`, and rule validation edge cases."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:actions_created_test.bzl",
    "actions_created_test",
)
load(
    "@build_bazel_rules_swift//test/rules:analysis_failure_test.bzl",
    "analysis_failure_test",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

_OPT_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "opt",
}

opt_action_command_line_test = make_action_command_line_test_rule(
    config_settings = _OPT_CONFIG_SETTINGS,
)

def swift_test_and_binary_test_suite(name, tags = []):
    """Test suite for `swift_test`, `swift_binary`, and rule validation edge cases.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # -------------------------------------------------------------------------
    # `swift_test` discovery mode tests
    # -------------------------------------------------------------------------

    # Mode 1: `srcs` present with `discover_tests = True` (default) compiles with
    # `-parse-as-library` and `-enable-testing` even in `opt` mode (where
    # `swift.enable_testing` is not enabled by default).
    opt_action_command_line_test(
        name = "{}_test_with_srcs_compile_flags".format(name),
        expected_argv = [
            "-parse-as-library",
            "-enable-testing",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:test_with_srcs",
    )

    # Mode 1 sets `SWIFT_TEST_DISCOVERY_MODULES` to the test target's own module
    # name.
    provider_test(
        name = "{}_test_with_srcs_discovery_modules_env".format(name),
        expected_values = [
            "SWIFT_TEST_DISCOVERY_MODULES=TestWithSrcs",
            "*",
        ],
        field = "environment",
        provider = "RunEnvironmentInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:test_with_srcs",
    )

    # Mode 2: Empty `srcs` with `discover_tests = True` links directly against
    # `deps` without creating `SwiftCompile` or `SwiftCompileModule` actions on
    # the `swift_test` target.
    actions_created_test(
        name = "{}_test_without_srcs_with_testonly_dep_no_compile_actions".format(name),
        mnemonics = [
            "-SwiftCompile",
            "-SwiftCompileModule",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:test_without_srcs_with_testonly_dep",
    )

    # Mode 2 sets `SWIFT_TEST_DISCOVERY_MODULES` to the direct dependencies'
    # Swift module names.
    provider_test(
        name = "{}_test_without_srcs_with_testonly_dep_discovery_modules_env".format(name),
        expected_values = [
            "SWIFT_TEST_DISCOVERY_MODULES=TestOnlyLib",
            "*",
        ],
        field = "environment",
        provider = "RunEnvironmentInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:test_without_srcs_with_testonly_dep",
    )

    # Mode 3: `discover_tests = False` omits `-parse-as-library` and (in `opt`
    # mode where `swift.enable_testing` is not enabled by default)
    # `-enable-testing` so `srcs` can provide its own `@main` or top-level code.
    opt_action_command_line_test(
        name = "{}_test_with_discover_tests_false_compile_flags".format(name),
        not_expected_argv = [
            "-parse-as-library",
            "-enable-testing",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:test_with_discover_tests_false",
    )

    # -------------------------------------------------------------------------
    # `swift_binary` entry-point renaming and `SwiftBinaryInfo` tests
    # -------------------------------------------------------------------------

    action_command_line_test(
        name = "{}_binary_entry_point_compile_flags".format(name),
        expected_argv = [
            "-Xfrontend -entry-point-function-name -Xfrontend MyBinary_main",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:binary_with_srcs",
    )

    action_command_line_test(
        name = "{}_binary_entry_point_link_flags".format(name),
        expected_argv = select({
            "@build_bazel_apple_support//constraints:apple": [
                "-Wl,-alias,_MyBinary_main,_main",
            ],
            "//conditions:default": [
                "-Wl,-defsym,main=MyBinary_main",
            ],
        }),
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:binary_with_srcs",
    )

    provider_test(
        name = "{}_binary_with_srcs_propagates_swift_binary_info".format(name),
        expected_values = ["MyBinary"],
        field = "swift_info.direct_modules.name",
        provider = "SwiftBinaryInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:binary_with_srcs",
    )

    provider_test(
        name = "{}_binary_without_srcs_does_not_propagate_swift_binary_info".format(name),
        does_not_propagate_provider = "SwiftBinaryInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:binary_without_srcs",
    )

    # -------------------------------------------------------------------------
    # `swift_library` `-parse-as-library` vs `main.swift` tests
    # -------------------------------------------------------------------------

    action_command_line_test(
        name = "{}_lib_without_main_passes_parse_as_library".format(name),
        expected_argv = ["-parse-as-library"],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:lib_without_main",
    )

    action_command_line_test(
        name = "{}_lib_with_main_omits_parse_as_library".format(name),
        not_expected_argv = ["-parse-as-library"],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:lib_with_main",
    )

    # -------------------------------------------------------------------------
    # Negative rule validation failure tests
    # -------------------------------------------------------------------------

    analysis_failure_test(
        name = "{}_lib_overlapping_deps_fails".format(name),
        expected_message = "'deps' and 'private_deps' must be disjoint, but the following targets were found in both:",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:lib_overlapping_deps",
    )

    analysis_failure_test(
        name = "{}_lib_no_swift_srcs_fails".format(name),
        expected_message = "A Swift module must have at least one Swift source file.",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:lib_no_swift_srcs",
    )

    analysis_failure_test(
        name = "{}_import_missing_module_and_interface_fails".format(name),
        expected_message = "One or both of 'swiftinterface' and 'swiftmodule' must be specified.",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:import_missing_module_and_interface",
    )

    analysis_failure_test(
        name = "{}_symbol_graph_duplicate_modules_fails".format(name),
        expected_message = "Module 'SomeModule' was provided by multiple targets.",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:symbol_graph_duplicate_modules",
    )

    native.test_suite(
        name = "{}_analysis_tests".format(name),
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tests = [
            ":{}_analysis_tests".format(name),
            "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:test_with_discover_tests_false",
            "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:test_with_srcs",
            "@build_bazel_rules_swift//test/fixtures/swift_test_and_binary:test_without_srcs_with_testonly_dep",
        ],
    )

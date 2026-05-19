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

"""Tests for the `swift.emit_localized_strings` feature."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)
load(
    "//test/rules:provider_test.bzl",
    "make_provider_test_rule",
)

localized_strings_action_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.emit_localized_strings",
        ],
    },
)

localized_strings_provider_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.emit_localized_strings",
        ],
    },
)

localized_strings_wmo_provider_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.emit_localized_strings",
        ],
        str(Label("//swift:copt")): [
            "-whole-module-optimization",
        ],
    },
)

localized_strings_split_action_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.emit_localized_strings",
            "swift.split_derived_files_generation",
        ],
    },
)

def localized_strings_test_suite(name, tags = []):
    """Test suite for the `swift.emit_localized_strings` feature.

    Args:
        name: The base name to be used in things created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # When the feature is disabled (the default), the compiler is not asked to
    # emit localized strings.
    action_command_line_test(
        name = "{}_disabled_by_default".format(name),
        not_expected_argv = ["-emit-localized-strings"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/multiple_files",
    )

    # When enabled, the compile action passes both the flag and the path,
    # pointing at the declared `.stringsdata` directory.
    localized_strings_action_test(
        name = "{}_enabled_passes_flags".format(name),
        expected_argv = [
            "-emit-localized-strings",
            "-emit-localized-strings-path",
            "test/fixtures/multiple_files/multiple_files.stringsdata",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/multiple_files",
    )

    # The declared directory is surfaced via the `swift_localized_strings`
    # output group (multiple source files, non-WMO).
    localized_strings_provider_test(
        name = "{}_output_group_multiple_files".format(name),
        expected_files = [
            "test/fixtures/multiple_files/multiple_files.stringsdata",
        ],
        field = "swift_localized_strings",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/multiple_files",
    )

    # A single directory output is produced under whole-module optimization as
    # well; the per-source `.stringsdata` files land inside it.
    localized_strings_wmo_provider_test(
        name = "{}_output_group_wmo".format(name),
        expected_files = [
            "test/fixtures/multiple_files/multiple_files.stringsdata",
        ],
        field = "swift_localized_strings",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/multiple_files",
    )

    localized_strings_provider_test(
        name = "{}_output_group_single_file".format(name),
        expected_files = [
            "test/fixtures/debug_settings/simple.stringsdata",
        ],
        field = "swift_localized_strings",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    # With split derived-files generation, emission stays on the compile action
    # (which produces objects) and is not added to the derive-files action.
    localized_strings_split_action_test(
        name = "{}_split_flag_on_compile".format(name),
        expected_argv = ["-emit-localized-strings"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/multiple_files",
    )

    localized_strings_split_action_test(
        name = "{}_split_flag_not_on_derive_files".format(name),
        not_expected_argv = ["-emit-localized-strings"],
        mnemonic = "SwiftDeriveFiles",
        tags = all_tags,
        target_under_test = "//test/fixtures/multiple_files",
    )

    # A target-level `-emit-localized-strings-path` copt is respected:
    # rules_swift does not declare its own directory or add its own flag, so
    # the path is not double-specified.
    localized_strings_action_test(
        name = "{}_user_path_override_respected".format(name),
        expected_argv = [
            "-emit-localized-strings-path /tmp/user/override",
        ],
        not_expected_argv = [
            "-emit-localized-strings",
            "multiple_files_localized_strings_path_override.stringsdata",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/multiple_files:multiple_files_localized_strings_path_override",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

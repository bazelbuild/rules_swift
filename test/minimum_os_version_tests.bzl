# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Tests for minimum_os_version attribute and versioned target triples."""

load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

default_test = make_action_command_line_test_rule()

split_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

def minimum_os_version_test_suite(name, tags = []):
    """Test suite for minimum_os_version compiler arguments.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Test that library with minimum_os_version has version in target triple.
    # We check for just the version appearing after "-target" which verifies the versioned
    # triple is being passed to the compiler (e.g., "-target arm64-apple-macos17.0").

    default_test(
        name = "{}_lib_with_min_os_has_version_in_triple".format(name),
        expected_argv = [
            "-target",
            # The version should appear in the target triple
            "17.0",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:lib_with_min_os",
        target_compatible_with = ["@platforms//os:macos"],
    )

    # Test that binary with minimum_os_version has version in target triple.
    default_test(
        name = "{}_bin_with_min_os_has_version_in_triple".format(name),
        expected_argv = [
            "-target",
            "17.0",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:bin_with_min_os",
        target_compatible_with = ["@platforms//os:macos"],
    )

    # Test that test with minimum_os_version has version in target triple.
    default_test(
        name = "{}_test_with_min_os_has_version_in_triple".format(name),
        expected_argv = [
            "-target",
            "17.0",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:test_with_min_os",
        target_compatible_with = ["@platforms//os:macos"],
    )

    # Test that other modes also have the version in target.
    split_test(
        name = "{}_split_derive_files_has_version_in_triple".format(name),
        expected_argv = [
            "-target",
            "17.0",
        ],
        mnemonic = "SwiftDeriveFiles",
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:lib_with_min_os",
        target_compatible_with = ["@platforms//os:macos"],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

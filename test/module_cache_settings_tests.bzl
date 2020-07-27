# Copyright 2020 The Bazel Authors. All rights reserved.
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

"""Tests for module cache related command line flags under various configs."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

use_global_module_cache_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.use_global_module_cache",
        ],
    },
)

use_tmpdir_for_module_cache_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.use_tmpdir_for_module_cache",
        ],
    },
)

def module_cache_settings_test_suite(name = "module_cache_settings"):
    """Test suite for module cache options.

    Args:
        name: The name prefix for all the nested tests
    """

    # Verify that a global module cache path is passed to swiftc.
    use_global_module_cache_action_command_line_test(
        name = "{}_global_module_cache_build".format(name),
        expected_argv = [
            "-module-cache-path",
            # Starlark doesn't have support for regular expression yet, so we
            # can't verify the whole argument here.
            "/bin/_swift_module_cache",
        ],
        not_expected_argv = [
            "-Xwrapped-swift=-ephemeral-module-cache",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    # Verify that a pre-defined shared module cache path in `/private/tmp` is
    # passed to swiftc.
    use_tmpdir_for_module_cache_action_command_line_test(
        name = "{}_tmpdir_module_cache_build".format(name),
        expected_argv = [
            "-module-cache-path",
            "/private/tmp/__build_bazel_rules_swift_module_cache",
        ],
        not_expected_argv = [
            "-Xwrapped-swift=-ephemeral-module-cache",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

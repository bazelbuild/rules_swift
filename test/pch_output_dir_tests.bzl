# Copyright 2021 The Bazel Authors. All rights reserved.
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

"""Tests for pch output dir command line flags"""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

pch_output_dir_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.use_pch_output_dir",
        ],
    },
)

def pch_output_dir_test_suite(name):
    """Test suite for pch output dir options.

    Args:
      name: the base name to be used in things created by this macro
    """

    # Verify that a pch dir is passed
    pch_output_dir_action_command_line_test(
        name = "{}_pch_output_dir".format(name),
        expected_argv = [
            "-pch-output-dir",
            # Starlark doesn't have support for regular expression yet, so we
            # can't verify the whole argument here. It has the configuration
            # fragment baked in.
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

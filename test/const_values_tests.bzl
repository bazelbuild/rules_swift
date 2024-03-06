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

"""Tests for `const_values`."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "make_provider_test_rule",
    "provider_test",
)

const_values_test = make_action_command_line_test_rule()

no_const_values_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "-swift._supports_const_value_extraction",
        ],
    },
)

const_values_wmo_test = make_provider_test_rule(
    config_settings = {
        str(Label("@build_bazel_rules_swift//swift:copt")): [
            "-whole-module-optimization",
        ],
    },
)

def const_values_test_suite(name):
    """Test suite for `swift_library` producing .swiftconstvalues files.

    Args:
      name: the base name to be used in things created by this macro
    """

    provider_test(
        name = "{}_empty_const_values_single_file".format(name),
        expected_files = [
            "test/fixtures/debug_settings/simple_objs/Empty.swift.swiftconstvalues",
        ],
        field = "const_values",
        provider = "OutputGroupInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    provider_test(
        name = "{}_empty_const_values_multiple_files".format(name),
        expected_files = [
            "test/fixtures/multiple_files/multiple_files_objs/Empty.swift.swiftconstvalues",
            "test/fixtures/multiple_files/multiple_files_objs/Empty2.swift.swiftconstvalues",
        ],
        field = "const_values",
        provider = "OutputGroupInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/multiple_files",
    )

    const_values_wmo_test(
        name = "{}_wmo_single_values_file".format(name),
        expected_files = [
            "test/fixtures/multiple_files/multiple_files.swiftconstvalues",
        ],
        field = "const_values",
        provider = "OutputGroupInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/multiple_files",
    )

    const_values_test(
        name = "{}_expected_argv".format(name),
        expected_argv = [
            "-Xfrontend -const-gather-protocols-file",
            "-Xfrontend swift/toolchains/config/const_extract_protocols.json",
            "-emit-const-values-path",
            "first.swift.swiftconstvalues",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/basic:first",
    )

    no_const_values_test(
        name = "{}_not_expected_argv".format(name),
        not_expected_argv = [
            "-Xfrontend -const-gather-protocols-file",
            "-Xfrontend swift/toolchains/config/const_extract_protocols.json",
            "-emit-const-values-path",
            "first.swift.swiftconstvalues",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/basic:first",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

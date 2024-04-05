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

"""Tests for `swift_interop_hint`."""

load(
    "@build_bazel_rules_swift//test/rules:analysis_failure_test.bzl",
    "analysis_failure_test",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

def interop_hints_test_suite(name = "interop_hints"):
    """Test suite for `swift_interop_hint`.

    Args:
        name: The name prefix for all the nested tests
    """

    # Verify that a hint with only a custom module name causes the `cc_library`
    # to propagate a `SwiftInfo` info with the expected auto-generated module
    # map.
    provider_test(
        name = "{}_hint_with_custom_module_name_builds".format(name),
        expected_files = [
            "test/fixtures/interop_hints/cc_lib_custom_module_name.swift.modulemap",
        ],
        field = "transitive_modules.clang.module_map!",
        provider = "SwiftInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/interop_hints:import_module_name_swift",
    )

    # Verify that a hint with a custom module map file causes the `cc_library`
    # to propagate a `SwiftInfo` info with that file.
    provider_test(
        name = "{}_hint_with_custom_module_map_builds".format(name),
        expected_files = [
            "test/fixtures/interop_hints/module.modulemap",
        ],
        field = "transitive_modules.clang.module_map!",
        provider = "SwiftInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/interop_hints:import_submodule_swift",
    )

    # Verify that the build fails if a hint provides `module_map` without
    # `module_name`.
    analysis_failure_test(
        name = "{}_fails_when_module_map_provided_without_module_name".format(name),
        expected_message = "'module_name' must be specified when 'module_map' is specified.",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/interop_hints:invalid_swift",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

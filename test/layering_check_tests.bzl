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

"""Tests for Swift layering check command line flags and inputs."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
)

visibility("private")

def layering_check_test_suite(name, tags = []):
    """Test suite for Swift layering check flags and inputs.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that in parallel compilation mode on `swift_library`,
    # `SwiftCompileModule` receives the `.deps-module-mapping` flag and input,
    # while `SwiftCompileCodegen` does not.
    action_command_line_test(
        name = "{}_lib_parallel_module_has_layering_check".format(name),
        expected_argv = [
            "lib_parallel.deps-module-mapping",
        ],
        expected_inputs = [
            "*",
            "lib_parallel.deps-module-mapping",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/layering_check:lib_parallel",
    )

    action_command_line_test(
        name = "{}_lib_parallel_codegen_omits_layering_check".format(name),
        expected_inputs = [
            "*",
            "-lib_parallel.deps-module-mapping",
        ],
        mnemonic = "SwiftCompileCodegen",
        not_expected_argv = [
            "lib_parallel.deps-module-mapping",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/layering_check:lib_parallel",
    )

    # Verify that when `swift._layering_check_on_codegen` is enabled in parallel
    # compilation mode, `SwiftCompileCodegen` receives the `.deps-module-mapping`
    # flag and input, while `SwiftCompileModule` does not.
    action_command_line_test(
        name = "{}_codegen_layering_module_omits_layering_check".format(name),
        expected_inputs = [
            "*",
            "-lib_codegen_layering.deps-module-mapping",
        ],
        mnemonic = "SwiftCompileModule",
        not_expected_argv = [
            "lib_codegen_layering.deps-module-mapping",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/layering_check:lib_codegen_layering",
    )

    action_command_line_test(
        name = "{}_codegen_layering_codegen_has_layering_check".format(name),
        expected_argv = [
            "lib_codegen_layering.deps-module-mapping",
        ],
        expected_inputs = [
            "*",
            "lib_codegen_layering.deps-module-mapping",
        ],
        mnemonic = "SwiftCompileCodegen",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/layering_check:lib_codegen_layering",
    )

    # Verify that `swift_binary` (which does not emit a `.swiftmodule` and
    # automatically enables `swift._layering_check_on_codegen`) places the
    # `.deps-module-mapping` flag and input on `SwiftCompileCodegen`.
    action_command_line_test(
        name = "{}_bin_parallel_codegen_has_layering_check".format(name),
        expected_argv = [
            "bin_parallel.deps-module-mapping",
        ],
        expected_inputs = [
            "*",
            "bin_parallel.deps-module-mapping",
        ],
        mnemonic = "SwiftCompileCodegen",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/layering_check:bin_parallel",
    )

    # Verify that in legacy single-action compilation mode
    # (`-swift.compile_in_parallel`), `SwiftCompile` receives the
    # `.deps-module-mapping` flag and input.
    action_command_line_test(
        name = "{}_lib_single_has_layering_check".format(name),
        expected_argv = [
            "lib_single.deps-module-mapping",
        ],
        expected_inputs = [
            "*",
            "lib_single.deps-module-mapping",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/layering_check:lib_single",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

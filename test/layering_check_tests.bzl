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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")
load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
)
load(
    "@build_bazel_rules_swift//test/rules:expected_files.bzl",
    "compare_expected_files",
)

visibility("private")

def _deps_module_mapping_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    mapping_actions = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic == "FileWrite" and
           action.outputs.to_list()[0].basename.endswith(".deps-module-mapping")
    ]
    if len(mapping_actions) != 1:
        unittest.fail(
            env,
            "Expected exactly one .deps-module-mapping FileWrite action on '{}', found {}.".format(
                target_under_test.label,
                len(mapping_actions),
            ),
        )
        return analysistest.end(env)

    modules = mapping_actions[0].content.splitlines()
    for expected in ctx.attr.expected_modules:
        if expected not in modules:
            unittest.fail(
                env,
                "Expected .deps-module-mapping for '{}' to contain '{}', actual modules: {}".format(
                    target_under_test.label,
                    expected,
                    modules,
                ),
            )
    for not_expected in ctx.attr.not_expected_modules:
        if not_expected in modules:
            unittest.fail(
                env,
                "Expected .deps-module-mapping for '{}' not to contain '{}', actual modules: {}".format(
                    target_under_test.label,
                    not_expected,
                    modules,
                ),
            )

    if ctx.attr.expected_compile_inputs:
        compile_actions = [
            action
            for action in analysistest.target_actions(env)
            if action.mnemonic in ("SwiftCompile", "SwiftCompileModule")
        ]
        if len(compile_actions) != 1:
            unittest.fail(
                env,
                "Expected exactly one SwiftCompile/SwiftCompileModule action on '{}', found {}.".format(
                    target_under_test.label,
                    len(compile_actions),
                ),
            )
            return analysistest.end(env)
        compare_expected_files(
            env,
            "inputs of {} action for target '{}'".format(
                compile_actions[0].mnemonic,
                target_under_test.label,
            ),
            ctx.attr.expected_compile_inputs,
            compile_actions[0].inputs,
        )

    return analysistest.end(env)

def _make_deps_module_mapping_test_rule(config_settings = {}):
    return analysistest.make(
        _deps_module_mapping_test_impl,
        attrs = {
            "expected_compile_inputs": attr.string_list(),
            "expected_modules": attr.string_list(),
            "not_expected_modules": attr.string_list(),
        },
        config_settings = config_settings,
    )

deps_module_mapping_test = _make_deps_module_mapping_test_rule()

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

    deps_module_mapping_test(
        name = "{}_lib_parallel_deps_module_mapping_contains_direct_deps".format(name),
        expected_modules = [
            "third_party_bazel_rules_rules_swift_test_fixtures_layering_check_dep",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/layering_check:lib_parallel",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

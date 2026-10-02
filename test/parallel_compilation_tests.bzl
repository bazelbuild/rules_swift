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

"""Tests for parallel compilation."""

load(
    "@bazel_skylib//lib:unittest.bzl",
    "analysistest",
    "asserts",
    "unittest",
)
load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "@build_bazel_rules_swift//test/rules:actions_created_test.bzl",
    "actions_created_test",
    "make_actions_created_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:expected_files.bzl",
    "compare_expected_files",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

opt_actions_create_test = make_actions_created_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
    },
)

opt_via_swiftcopt_actions_create_test = make_actions_created_test_rule(
    config_settings = {
        "@build_bazel_rules_swift//swift:copt": ["-O"],
    },
)

opt_osize_via_swiftcopt_actions_create_test = make_actions_created_test_rule(
    config_settings = {
        "@build_bazel_rules_swift//swift:copt": ["-Osize"],
    },
)

opt_ounchecked_via_swiftcopt_actions_create_test = make_actions_created_test_rule(
    config_settings = {
        "@build_bazel_rules_swift//swift:copt": ["-Ounchecked"],
    },
)

opt_with_wmo_via_swiftcopt_actions_create_test = make_actions_created_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
        "@build_bazel_rules_swift//swift:copt": [
            "-whole-module-optimization",
        ],
    },
)

opt_with_force_single_frontend_via_swiftcopt_actions_create_test = make_actions_created_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
        "@build_bazel_rules_swift//swift:copt": [
            "-force-single-frontend-invocation",
        ],
    },
)

def _parallel_action_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    actions = analysistest.target_actions(env)

    mnemonic = ctx.attr.mnemonic
    matching_actions = [a for a in actions if a.mnemonic == mnemonic]
    if len(matching_actions) != 1:
        unittest.fail(
            env,
            "Expected exactly 1 '{}' action on '{}', but found {}.".format(
                mnemonic,
                target_under_test.label,
                len(matching_actions),
            ),
        )
        return analysistest.end(env)

    action = matching_actions[0]
    concatenated_args = " ".join(action.argv) + " "

    for expected in ctx.attr.expected_argv:
        if expected + " " not in concatenated_args:
            unittest.fail(
                env,
                "In {} action for '{}', expected argv to contain '{}', got: {}".format(
                    mnemonic,
                    target_under_test.label,
                    expected,
                    action.argv,
                ),
            )

    for not_expected in ctx.attr.not_expected_argv:
        if not_expected + " " in concatenated_args:
            unittest.fail(
                env,
                "In {} action for '{}', expected argv to not contain '{}', got: {}".format(
                    mnemonic,
                    target_under_test.label,
                    not_expected,
                    action.argv,
                ),
            )

    for substr in ctx.attr.expected_arg_substrings:
        if not any([substr in arg for arg in action.argv]):
            unittest.fail(
                env,
                "In {} action for '{}', expected an arg containing '{}', got: {}".format(
                    mnemonic,
                    target_under_test.label,
                    substr,
                    action.argv,
                ),
            )

    for substr in ctx.attr.not_expected_arg_substrings:
        if any([substr in arg for arg in action.argv]):
            unittest.fail(
                env,
                "In {} action for '{}', expected no arg containing '{}', got: {}".format(
                    mnemonic,
                    target_under_test.label,
                    substr,
                    action.argv,
                ),
            )

    if ctx.attr.expected_inputs:
        compare_expected_files(
            env,
            "inputs of {} action for '{}'".format(mnemonic, target_under_test.label),
            ctx.attr.expected_inputs,
            action.inputs,
        )

    if ctx.attr.expected_outputs:
        compare_expected_files(
            env,
            "outputs of {} action for '{}'".format(mnemonic, target_under_test.label),
            ctx.attr.expected_outputs,
            action.outputs,
        )

    return analysistest.end(env)

def _make_parallel_action_test_rule(config_settings = {}):
    return analysistest.make(
        _parallel_action_test_impl,
        attrs = {
            "expected_argv": attr.string_list(),
            "not_expected_argv": attr.string_list(),
            "expected_arg_substrings": attr.string_list(),
            "not_expected_arg_substrings": attr.string_list(),
            "expected_inputs": attr.string_list(),
            "expected_outputs": attr.string_list(),
            "mnemonic": attr.string(mandatory = True),
        },
        config_settings = config_settings,
    )

parallel_action_test = _make_parallel_action_test_rule()

opt_parallel_action_test = _make_parallel_action_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
    },
)

def _codegen_batching_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    module_actions = [a for a in actions if a.mnemonic == "SwiftCompileModule"]
    codegen_actions = [a for a in actions if a.mnemonic == "SwiftCompileCodegen"]

    asserts.equals(
        env,
        1,
        len(module_actions),
        "Expected exactly 1 SwiftCompileModule action.",
    )
    asserts.equals(
        env,
        ctx.attr.expected_codegen_batches,
        len(codegen_actions),
        "Expected {} SwiftCompileCodegen action(s), but found {}.".format(
            ctx.attr.expected_codegen_batches,
            len(codegen_actions),
        ),
    )

    for idx, action in enumerate(codegen_actions):
        batch_num = idx + 1
        obj_outputs = [
            out.path
            for out in action.outputs.to_list()
            if out.path.endswith(".o")
        ]
        if ctx.attr.expected_batch_object_counts:
            asserts.equals(
                env,
                ctx.attr.expected_batch_object_counts[idx],
                len(obj_outputs),
                "Unexpected number of .o outputs in batch {}.".format(batch_num),
            )

        if len(codegen_actions) == 1:
            expected_compile_step = "-Xwrapped-swift=-compile-step=SwiftCompileCodegen="
        else:
            expected_compile_step = (
                "-Xwrapped-swift=-compile-step=SwiftCompileCodegen=" +
                ",".join(obj_outputs)
            )
        asserts.true(
            env,
            expected_compile_step in action.argv,
            "Expected '{}' in batch {} argv, got: {}".format(
                expected_compile_step,
                batch_num,
                action.argv,
            ),
        )

        if ctx.attr.expect_indexed_macro_expansion_dirs:
            expected_macro_dir_suffix = "-{}.macro-expansions".format(batch_num)
            has_macro_dir = any([
                arg.startswith("-Xwrapped-swift=-macro-expansion-dir=") and
                arg.endswith(expected_macro_dir_suffix)
                for arg in action.argv
            ])
            asserts.true(
                env,
                has_macro_dir,
                "Expected macro expansion dir ending with '{}' in batch {} argv.".format(
                    expected_macro_dir_suffix,
                    batch_num,
                ),
            )

        if ctx.attr.expect_layering_check_only_on_first_batch:
            has_layering_check = any([
                arg.startswith("-Xwrapped-swift=-layering-check-deps-modules=")
                for arg in action.argv
            ])
            if batch_num == 1:
                asserts.true(
                    env,
                    has_layering_check,
                    "Expected layering check flag on first codegen batch.",
                )
            else:
                asserts.false(
                    env,
                    has_layering_check,
                    "Did not expect layering check flag on codegen batch {}.".format(
                        batch_num,
                    ),
                )

    return analysistest.end(env)

codegen_batching_test = analysistest.make(
    _codegen_batching_test_impl,
    attrs = {
        "expected_codegen_batches": attr.int(mandatory = True),
        "expected_batch_object_counts": attr.int_list(),
        "expect_indexed_macro_expansion_dirs": attr.bool(default = False),
        "expect_layering_check_only_on_first_batch": attr.bool(default = False),
    },
)

def parallel_compilation_test_suite(name, tags = []):
    """Test suite for parallel compilation.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Non-optimized, non-WMO can be compiled in parallel.
    actions_created_test(
        name = "{}_no_opt_no_wmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    # Non-optimized, with-WMO can be compiled in parallel.
    actions_created_test(
        name = "{}_no_opt_with_wmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
    )

    # Optimized, non-WMO can be compiled in parallel.
    actions_created_test(
        name = "{}_with_opt_no_wmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_no_wmo",
    )

    # Optimized, with-WMO can be compiled in parallel if CMO is also disabled.
    actions_created_test(
        name = "{}_with_opt_with_wmo_no_cmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_no_cmo",
    )

    # Optimized, with-WMO cannot be compiled in parallel if CMO is enabled.
    actions_created_test(
        name = "{}_with_opt_with_wmo_with_cmo".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_cmo",
    )

    # Force `-c opt` on a non-optimized, with-WMO target and make sure we don't
    # plan parallel compilation there.
    opt_actions_create_test(
        name = "{}_no_opt_with_wmo_but_compilation_mode_opt".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
    )

    # Force `-O` using the `copt` flag on a non-optimized, with-WMO target and
    # make sure we don't plan parallel compilation there.
    opt_via_swiftcopt_actions_create_test(
        name = "{}_no_opt_with_wmo_but_swiftcopt_dash_O".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
    )

    # Force `-Osize` and `-Ounchecked` using the `copt` flag on a non-optimized,
    # with-WMO target and make sure we don't plan parallel compilation there.
    opt_osize_via_swiftcopt_actions_create_test(
        name = "{}_no_opt_with_wmo_but_swiftcopt_dash_Osize".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
    )

    opt_ounchecked_via_swiftcopt_actions_create_test(
        name = "{}_no_opt_with_wmo_but_swiftcopt_dash_Ounchecked".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
    )

    # Optimized, with-WMO can be compiled in parallel if library evolution is
    # enabled (which implicitly disables CMO).
    actions_created_test(
        name = "{}_with_opt_with_wmo_with_library_evolution".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_library_evolution",
    )

    # Make sure that when we look for optimizer flags, we don't treat `-Onone`
    # as being optimized.
    actions_created_test(
        name = "{}_onone_with_wmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:onone_with_wmo",
    )

    # Optimized (via `-c opt`) with-WMO cannot be compiled in parallel if CMO is
    # enabled (the default).
    opt_with_wmo_via_swiftcopt_actions_create_test(
        name = "{}_with_opt_via_compilation_mode_opt_with_wmo".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    # Optimized (via `-c opt`) with `-force-single-frontend-invocation` in
    # swiftcopts is treated as WMO and falls back to SwiftCompile.
    opt_with_force_single_frontend_via_swiftcopt_actions_create_test(
        name = "{}_with_opt_via_compilation_mode_opt_with_force_single_frontend".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    # Verify `-Xwrapped-swift=-compile-step=` flag partitioning across
    # SwiftCompileModule, SwiftCompileCodegen, and legacy SwiftCompile.
    parallel_action_test(
        name = "{}_compile_step_module_flag".format(name),
        expected_arg_substrings = [
            "-Xwrapped-swift=-compile-step=SwiftCompileModule=",
            "no_opt_no_wmo.swiftmodule",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    parallel_action_test(
        name = "{}_compile_step_codegen_single_batch_flag".format(name),
        expected_argv = [
            "-Xwrapped-swift=-compile-step=SwiftCompileCodegen=",
        ],
        mnemonic = "SwiftCompileCodegen",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    parallel_action_test(
        name = "{}_compile_step_not_on_legacy_compile".format(name),
        mnemonic = "SwiftCompile",
        not_expected_arg_substrings = [
            "-Xwrapped-swift=-compile-step=",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_cmo",
    )

    # Verify that `-Xwrapped-swift=-macro-expansion-dir=` is only passed to
    # SwiftCompileCodegen (not SwiftCompileModule) in fastbuild/dbg, and omitted
    # in `-c opt`.
    parallel_action_test(
        name = "{}_macro_expansion_dir_on_codegen".format(name),
        expected_arg_substrings = [
            "-Xwrapped-swift=-macro-expansion-dir=",
        ],
        expected_outputs = [
            "no_opt_no_wmo.macro-expansions",
            "*",
        ],
        mnemonic = "SwiftCompileCodegen",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    parallel_action_test(
        name = "{}_macro_expansion_dir_not_on_module".format(name),
        expected_outputs = [
            "-no_opt_no_wmo.macro-expansions",
            "*",
        ],
        mnemonic = "SwiftCompileModule",
        not_expected_arg_substrings = [
            "-Xwrapped-swift=-macro-expansion-dir=",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    opt_parallel_action_test(
        name = "{}_macro_expansion_dir_omitted_in_opt".format(name),
        expected_outputs = [
            "-no_opt_no_wmo.macro-expansions",
            "*",
        ],
        mnemonic = "SwiftCompileCodegen",
        not_expected_arg_substrings = [
            "-Xwrapped-swift=-macro-expansion-dir=",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    # Verify that generated Objective-C header and module interface flags and
    # outputs are partitioned onto SwiftCompileModule and excluded from
    # SwiftCompileCodegen.
    parallel_action_test(
        name = "{}_header_and_interface_on_module".format(name),
        expected_argv = [
            "-emit-objc-header-path",
            "-emit-module-interface-path",
        ],
        expected_outputs = [
            "header_and_interface-Swift.h",
            "header_and_interface.swiftinterface",
            "header_and_interface.swiftmodule",
            "-Empty.swift.o",
            "*",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:header_and_interface",
    )

    parallel_action_test(
        name = "{}_header_and_interface_not_on_codegen".format(name),
        expected_outputs = [
            "Empty.swift.o",
            "-header_and_interface-Swift.h",
            "-header_and_interface.swiftinterface",
            "-header_and_interface.swiftmodule",
            "*",
        ],
        mnemonic = "SwiftCompileCodegen",
        not_expected_argv = [
            "-emit-objc-header-path",
            "-emit-module-interface-path",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:header_and_interface",
    )

    # Verify that `-Xwrapped-swift=-layering-check-deps-modules=` is placed on
    # SwiftCompileModule by default, and moves to SwiftCompileCodegen when
    # `swift._layering_check_on_codegen` is enabled.
    parallel_action_test(
        name = "{}_layering_check_default_on_module".format(name),
        expected_arg_substrings = [
            "-Xwrapped-swift=-layering-check-deps-modules=",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    parallel_action_test(
        name = "{}_layering_check_default_not_on_codegen".format(name),
        mnemonic = "SwiftCompileCodegen",
        not_expected_arg_substrings = [
            "-Xwrapped-swift=-layering-check-deps-modules=",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    parallel_action_test(
        name = "{}_layering_check_on_codegen_not_on_module".format(name),
        mnemonic = "SwiftCompileModule",
        not_expected_arg_substrings = [
            "-Xwrapped-swift=-layering-check-deps-modules=",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:layering_check_on_codegen",
    )

    parallel_action_test(
        name = "{}_layering_check_on_codegen_present_on_codegen".format(name),
        expected_arg_substrings = [
            "-Xwrapped-swift=-layering-check-deps-modules=",
        ],
        mnemonic = "SwiftCompileCodegen",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:layering_check_on_codegen",
    )

    # Verify that `-enable-batch-mode` is only added to legacy `SwiftCompile`
    # and not to `SwiftCompileModule` or `SwiftCompileCodegen`.
    parallel_action_test(
        name = "{}_batch_mode_not_on_module".format(name),
        mnemonic = "SwiftCompileModule",
        not_expected_argv = ["-enable-batch-mode"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    parallel_action_test(
        name = "{}_batch_mode_not_on_codegen".format(name),
        mnemonic = "SwiftCompileCodegen",
        not_expected_argv = ["-enable-batch-mode"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    parallel_action_test(
        name = "{}_batch_mode_on_legacy_compile".format(name),
        expected_argv = ["-enable-batch-mode"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:legacy_batch_mode",
    )

    # Verify index-while-building flag and output partitioning: the `.indexstore`
    # output directory is declared only on SwiftCompileCodegen, not on
    # SwiftCompileModule.
    parallel_action_test(
        name = "{}_index_while_building_on_codegen".format(name),
        expected_argv = [
            "-index-store-path",
            "-index-ignore-clang-modules",
        ],
        expected_outputs = [
            "index_while_building.indexstore",
            "*",
        ],
        mnemonic = "SwiftCompileCodegen",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:index_while_building",
    )

    parallel_action_test(
        name = "{}_index_while_building_not_on_module".format(name),
        expected_outputs = [
            "-index_while_building.indexstore",
            "*",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:index_while_building",
    )

    # Verify constant value extraction flag, input, and output partitioning:
    # `.swiftconstvalues` outputs are declared only on SwiftCompileCodegen (both
    # per-file and whole-module WMO), not on SwiftCompileModule.
    parallel_action_test(
        name = "{}_const_values_on_codegen".format(name),
        expected_arg_substrings = [
            "const_values_const_extract_protocols.json",
        ],
        expected_argv = [
            "-emit-const-values",
            "-Xfrontend -const-gather-protocols-file",
        ],
        expected_inputs = [
            "const_values_const_extract_protocols.json",
            "*",
        ],
        expected_outputs = [
            "Empty.swift.swiftconstvalues",
            "*",
        ],
        mnemonic = "SwiftCompileCodegen",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:const_values",
    )

    parallel_action_test(
        name = "{}_const_values_not_on_module".format(name),
        expected_outputs = [
            "-Empty.swift.swiftconstvalues",
            "*",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:const_values",
    )

    parallel_action_test(
        name = "{}_const_values_wmo_on_codegen".format(name),
        expected_arg_substrings = [
            "const_values_wmo_const_extract_protocols.json",
        ],
        expected_argv = [
            "-emit-const-values",
            "-Xfrontend -const-gather-protocols-file",
        ],
        expected_inputs = [
            "const_values_wmo_const_extract_protocols.json",
            "*",
        ],
        expected_outputs = [
            "const_values_wmo.swiftconstvalues",
            "const_values_wmo_objs/Empty.swift.o",
            "*",
        ],
        mnemonic = "SwiftCompileCodegen",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:const_values_wmo",
    )

    # Verify codegen batching when len(srcs) > codegen_batch_size (9 > 8),
    # per-batch layering check placement, and single-batch fallback when
    # index_while_building is enabled.
    codegen_batching_test(
        name = "{}_multi_batch_codegen".format(name),
        expect_indexed_macro_expansion_dirs = True,
        expected_batch_object_counts = [8, 1],
        expected_codegen_batches = 2,
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:multi_batch",
    )

    codegen_batching_test(
        name = "{}_multi_batch_layering_check_on_first_batch_only".format(name),
        expect_layering_check_only_on_first_batch = True,
        expected_batch_object_counts = [8, 1],
        expected_codegen_batches = 2,
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:multi_batch_layering_check_on_codegen",
    )

    codegen_batching_test(
        name = "{}_multi_batch_collapses_when_indexing".format(name),
        expected_batch_object_counts = [9],
        expected_codegen_batches = 1,
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:multi_batch_with_indexing",
    )

    # Verify supplemental output groups produced by parallel compilation.
    provider_test(
        name = "{}_macro_expansions_output_group".format(name),
        expected_files = ["no_opt_no_wmo.macro-expansions"],
        field = "macro_expansions",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    provider_test(
        name = "{}_multi_batch_macro_expansions_output_group".format(name),
        expected_files = [
            "multi_batch-1.macro-expansions",
            "multi_batch-2.macro-expansions",
        ],
        field = "macro_expansions",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:multi_batch",
    )

    provider_test(
        name = "{}_indexstore_output_group".format(name),
        expected_files = ["index_while_building.indexstore"],
        field = "indexstore",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:index_while_building",
    )

    provider_test(
        name = "{}_const_values_output_group".format(name),
        expected_files = ["Empty.swift.swiftconstvalues"],
        field = "const_values",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:const_values",
    )

    provider_test(
        name = "{}_const_values_wmo_output_group".format(name),
        expected_files = ["const_values_wmo.swiftconstvalues"],
        field = "const_values",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:const_values_wmo",
    )

    # The analysis tests verify that we register the actions we expect. Use a
    # `build_test` to make sure the actions execute successfully.
    build_test(
        name = "{}_build_test".format(name),
        targets = [
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_no_wmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_no_cmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_cmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_library_evolution",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:onone_with_wmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:header_and_interface",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:layering_check_on_codegen",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:legacy_batch_mode",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:index_while_building",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:multi_batch",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:multi_batch_layering_check_on_codegen",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:multi_batch_with_indexing",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:const_values",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:const_values_wmo",
        ],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

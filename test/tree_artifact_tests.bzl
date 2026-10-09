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

"""Tests for directories (tree artifacts) in `srcs`, and for `srcs_dirs`."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
)
load("//test/rules:action_inputs_test.bzl", "action_inputs_test")
load("//test/rules:analysis_failure_test.bzl", "analysis_failure_test")
load(
    "//test/rules:output_file_map_test.bzl",
    "make_output_file_map_test_rule",
    "output_file_map_test",
)

_EXPAND_FLAG = "-Xwrapped-swift=-expand-output-file-map"

_OBJS = "test/fixtures/tree_artifact/tree_artifact_objs/generated.swift"

output_file_map_emit_bc_test = make_output_file_map_test_rule(
    config_settings = {
        "//command_line_option:features": ["swift.emit_bc"],
    },
)

output_file_map_split_derived_files_test = make_output_file_map_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

def tree_artifact_test_suite(name, tags = []):
    """Test suite for directories (tree artifacts) in `srcs`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # A directory's entry has output directories, which the worker expands for
    # each Swift file in it at execution time.
    output_file_map_test(
        name = "{}_output_file_map".format(name),
        expected_mapping = {
            "ast-dump": _OBJS + "_ast",
            "const-values": _OBJS + "_swiftconstvalues",
            "object": _OBJS + "_o",
        },
        file_entry = "test/fixtures/tree_artifact/generated.swift",
        output_file_map = "test/fixtures/tree_artifact/tree_artifact.output_file_map.json",
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifact",
    )

    output_file_map_emit_bc_test(
        name = "{}_output_file_map_emit_bc".format(name),
        expected_mapping = {
            "llvm-bc": _OBJS + "_bc",
        },
        file_entry = "test/fixtures/tree_artifact/generated.swift",
        output_file_map = "test/fixtures/tree_artifact/tree_artifact.output_file_map.json",
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifact",
    )

    # The worker adds each file's name and extension to the object directory.
    output_file_map_split_derived_files_test(
        name = "{}_derived_output_file_map".format(name),
        expected_mapping = {
            "swift-dependencies": _OBJS + "_o",
        },
        file_entry = "test/fixtures/tree_artifact/generated.swift",
        output_file_map = "test/fixtures/tree_artifact/tree_artifact.derived_output_file_map.json",
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifact",
    )

    # The worker only expands the output file map of targets with directories.
    action_command_line_test(
        name = "{}_compile_expands_output_file_map".format(name),
        expected_argv = [_EXPAND_FLAG],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifact",
    )

    action_command_line_test(
        name = "{}_dump_ast_expands_output_file_map".format(name),
        expected_argv = [_EXPAND_FLAG],
        mnemonic = "SwiftDumpAST",
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifact",
    )

    action_command_line_test(
        name = "{}_no_expansion_without_directories".format(name),
        not_expected_argv = [_EXPAND_FLAG],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    # A binary's own objects from a directory are linked from an always-linked
    # archive; other binaries link their objects directly.
    action_inputs_test(
        name = "{}_binary_links_objects_archive".format(name),
        expected_inputs = ["libtree_artifact_main_binary_srcs.lo"],
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifact:tree_artifact_main_binary",
    )

    action_inputs_test(
        name = "{}_binary_without_directories_links_objects".format(name),
        not_expected_inputs = ["libtree_artifact_binary_srcs.lo"],
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifact:tree_artifact_binary",
    )

    # A checked-in directory in `srcs_dirs` is passed as a single path, which
    # the worker replaces with the Swift files in it.
    output_file_map_test(
        name = "{}_source_directory_output_file_map".format(name),
        expected_mapping = {
            "ast-dump": "test/fixtures/source_directory/source_directory_objs/Sources_ast",
            "object": "test/fixtures/source_directory/source_directory_objs/Sources_o",
        },
        file_entry = "test/fixtures/source_directory/Sources",
        output_file_map = "test/fixtures/source_directory/source_directory.output_file_map.json",
        tags = all_tags,
        target_under_test = "//test/fixtures/source_directory",
    )

    action_command_line_test(
        name = "{}_source_directory_expanded".format(name),
        expected_argv = [
            "-Xwrapped-swift=-expand-source-directory=test/fixtures/source_directory/Sources",
            _EXPAND_FLAG,
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/source_directory",
    )

    # Bazel already expands tree artifacts on the command line.
    action_command_line_test(
        name = "{}_tree_artifact_not_expanded_by_worker".format(name),
        not_expected_argv = ["-Xwrapped-swift=-expand-source-directory"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifact",
    )

    analysis_failure_test(
        name = "{}_file_in_srcs_dirs".format(name),
        expected_message = "in srcs_dirs is not a directory",
        tags = all_tags,
        target_under_test = "//test/fixtures/source_directory:file_in_srcs_dirs",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

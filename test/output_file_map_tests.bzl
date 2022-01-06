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

"""Tests for `output_file_map`."""

load(
    "@build_bazel_rules_swift//test/rules:output_file_map_test.bzl",
    "make_output_file_map_test_rule",
    "output_file_map_test",
)

output_file_map_embed_bitcode_test = make_output_file_map_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.bitcode_embedded",
        ],
    },
)

output_file_map_embed_bitcode_wmo_test = make_output_file_map_test_rule(
    config_settings = {
        "//command_line_option:swiftcopt": [
            "-whole-module-optimization",
        ],
        "//command_line_option:features": [
            "swift.bitcode_embedded",
        ],
    },
)

def output_file_map_test_suite(name):
    """Test suite for `swift_library` generating output file maps.

    Args:
      name: the base name to be used in things created by this macro
    """

    output_file_map_test(
        name = "{}_without_bitcode".format(name),
        expected_mapping = {
            "object": "test/fixtures/debug_settings/simple_objs/Empty.swift.o",
        },
        file_entry = "test/fixtures/debug_settings/Empty.swift",
        output_file_map = "test/fixtures/debug_settings/simple.output_file_map.json",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    # In Xcode13, the bitcode file needs to be in the output file map
    # (https://github.com/bazelbuild/rules_swift/issues/682).
    output_file_map_embed_bitcode_test(
        name = "{}_embed_bitcode".format(name),
        expected_mapping = {
            "llvm-bc": "test/fixtures/debug_settings/simple_objs/Empty.swift.bc",
            "object": "test/fixtures/debug_settings/simple_objs/Empty.swift.o",
        },
        file_entry = "test/fixtures/debug_settings/Empty.swift",
        output_file_map = "test/fixtures/debug_settings/simple.output_file_map.json",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    output_file_map_embed_bitcode_wmo_test(
        name = "{}_embed_bitcode_wmo".format(name),
        expected_mapping = {
            "llvm-bc": "test/fixtures/debug_settings/simple_objs/Empty.swift.bc",
            "object": "test/fixtures/debug_settings/simple_objs/Empty.swift.o",
        },
        file_entry = "test/fixtures/debug_settings/Empty.swift",
        output_file_map = "test/fixtures/debug_settings/simple.output_file_map.json",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

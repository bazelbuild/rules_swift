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

"""Tests for default index-store compression and index-import compatibility."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//test/rules:action_command_line_test.bzl", "make_action_command_line_test_rule")

indexing_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": ["swift.index_while_building"],
    },
)

no_indexing_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": ["swift.index_store_compress"],
    },
)

disabled_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.index_while_building",
            "-swift.index_store_compress",
        ],
    },
)

split_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.index_while_building",
            "swift.split_derived_files_generation",
        ],
    },
)

modular_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.index_while_building",
            "swift.modular_indexing",
            "swift.emit_c_module",
            "swift.use_c_modules",
        ],
    },
)

def index_store_compress_test_suite(name):
    """Tests compression with the configured toolchain when supported.

    Args:
        name: The base name of the generated tests.
    """
    all_tags = [name]

    supported_toolchain = select({
        "//test:xcode_26_4_or_newer": [],
        "@platforms//os:linux": [],
        "//conditions:default": ["@platforms//:incompatible"],
    })

    indexing_test(
        name = "{}_enabled_by_default".format(name),
        expected_argv = ["-index-store-path", "-Xfrontend -index-store-compress"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = supported_toolchain,
        target_under_test = "//test/fixtures/basic:first",
    )

    no_indexing_test(
        name = "{}_no_indexing".format(name),
        not_expected_argv = ["-index-store-compress"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = supported_toolchain,
        target_under_test = "//test/fixtures/basic:first",
    )

    disabled_test(
        name = "{}_disabled".format(name),
        not_expected_argv = ["-index-store-compress"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = supported_toolchain,
        target_under_test = "//test/fixtures/basic:first",
    )

    indexing_test(
        name = "{}_module_interface".format(name),
        expected_argv = ["-index-store-path", "-index-store-compress"],
        not_expected_argv = ["-Xfrontend"],
        mnemonic = "SwiftCompileModuleInterface",
        tags = all_tags,
        target_compatible_with = supported_toolchain,
        target_under_test = "//test/fixtures/module_interface:toy_module_interface",
    )

    split_test(
        name = "{}_split_compile".format(name),
        expected_argv = ["-Xfrontend -index-store-compress"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = supported_toolchain,
        target_under_test = "//test/fixtures/basic:first",
    )

    split_test(
        name = "{}_split_derive_files".format(name),
        not_expected_argv = ["-index-store-compress"],
        mnemonic = "SwiftDeriveFiles",
        tags = all_tags,
        target_compatible_with = supported_toolchain,
        target_under_test = "//test/fixtures/basic:first",
    )

    modular_test(
        name = "{}_system_pcm".format(name),
        expected_argv = ["-index-store-path", "-Xfrontend -index-store-compress"],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"] + supported_toolchain,
        target_under_test = "@system_sdk//:Foundation_clang",
    )

    sh_test(
        name = "{}_index_import".format(name),
        srcs = ["//test/fixtures/global_index_store:check_compressed_index.sh"],
        args = ["$(rootpath //test/fixtures/global_index_store:indexstore)"],
        data = ["//test/fixtures/global_index_store:indexstore"],
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"] + supported_toolchain,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

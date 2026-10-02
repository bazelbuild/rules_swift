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

"""Tests for `swift_compiler_plugin` and `swift_compiler_plugin_import`."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:analysis_failure_test.bzl",
    "analysis_failure_test",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

parallel_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": ["swift.compile_in_parallel"],
    },
)

legacy_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": ["-swift.compile_in_parallel"],
    },
)

def compiler_plugin_test_suite(name, tags = []):
    """Test suite for `swift_compiler_plugin` and `swift_compiler_plugin_import`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that `swift_compiler_plugin` compiles with `-parse-as-library` and
    # renames its entry point to `<module_name>_main` across both parallel
    # (`SwiftCompileModule` and `SwiftCompileCodegen`) and legacy
    # (`SwiftCompile`) compilation modes.
    for mode_name, test_rule, mnemonics in [
        ("parallel", parallel_action_command_line_test, ["SwiftCompileModule", "SwiftCompileCodegen"]),
        ("legacy", legacy_action_command_line_test, ["SwiftCompile"]),
    ]:
        for mnemonic in mnemonics:
            test_rule(
                name = "{}_plugin_compile_flags_{}_{}".format(
                    name,
                    mode_name,
                    mnemonic.lower(),
                ),
                expected_argv = [
                    "-parse-as-library",
                    "-Xfrontend -entry-point-function-name -Xfrontend MyPlugin_main",
                ],
                mnemonic = mnemonic,
                tags = all_tags,
                target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:plugin",
            )

            test_rule(
                name = "{}_default_module_plugin_compile_flags_{}_{}".format(
                    name,
                    mode_name,
                    mnemonic.lower(),
                ),
                expected_argv = [
                    "-parse-as-library",
                    "-Xfrontend -entry-point-function-name -Xfrontend",
                    "test_fixtures_compiler_plugin_default_module_plugin_main",
                ],
                mnemonic = mnemonic,
                tags = all_tags,
                target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:default_module_plugin",
            )

    # Verify that linking a `swift_compiler_plugin` executable aliases `main`
    # to `<module_name>_main`.
    action_command_line_test(
        name = "{}_plugin_link_entry_point_flags".format(name),
        expected_argv = select({
            "@build_bazel_apple_support//constraints:apple": [
                "-Wl,-alias,_MyPlugin_main,_main",
            ],
            "//conditions:default": [
                "-Wl,-defsym,main=MyPlugin_main",
            ],
        }),
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:plugin",
    )

    # Verify that `swift_compiler_plugin` propagates `SwiftBinaryInfo` (and not
    # a top-level `SwiftInfo`) so that `swift_test` targets can depend on it for
    # unit testing without allowing arbitrary `swift_library` targets to depend
    # on it.
    provider_test(
        name = "{}_plugin_does_not_propagate_swift_info".format(name),
        does_not_propagate_provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:plugin",
    )

    provider_test(
        name = "{}_plugin_propagates_swift_binary_info_module_name".format(name),
        expected_values = ["MyPlugin"],
        field = "swift_info.direct_modules.name",
        provider = "SwiftBinaryInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:plugin",
    )

    provider_test(
        name = "{}_plugin_propagates_swift_binary_info_swiftmodule".format(name),
        expected_files = [
            "MyPlugin.swiftmodule",
        ],
        field = "swift_info.direct_modules.swift!.swiftmodule",
        provider = "SwiftBinaryInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:plugin",
    )

    # Verify that a `swift_test` depending on a `swift_compiler_plugin` in `deps`
    # receives the plugin's `.swiftmodule` during compilation and does NOT
    # receive the plugin's custom entry point linker alias when linking the test
    # runner binary.
    action_command_line_test(
        name = "{}_plugin_unit_test_compiles_against_plugin_module".format(name),
        expected_inputs = [
            "MyPlugin.swiftmodule",
            "*",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:plugin_unit_test",
    )

    action_command_line_test(
        name = "{}_plugin_unit_test_link_does_not_alias_plugin_main".format(name),
        mnemonic = "CppLink",
        not_expected_argv = [
            "-Wl,-alias,_MyPlugin_main,_main",
            "-Wl,-defsym,main=MyPlugin_main",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:plugin_unit_test",
    )

    # Verify that a target with `plugins = [":plugin"]` and its direct consumer
    # pass `-Xfrontend -load-plugin-executable -Xfrontend <exec>#MyPlugin` and
    # include the plugin executable in action inputs across both parallel
    # (`SwiftCompileModule`, `SwiftCompileCodegen`) and legacy (`SwiftCompile`)
    # compilation modes.
    for mode_name, test_rule, mnemonics in [
        ("parallel", parallel_action_command_line_test, ["SwiftCompileModule", "SwiftCompileCodegen"]),
        ("legacy", legacy_action_command_line_test, ["SwiftCompile"]),
    ]:
        for mnemonic in mnemonics:
            for target_name in [
                "macro_library",
                "direct_consumer",
                "reexported_consumer",
                "binary_with_plugin",
                "test_with_plugin",
            ]:
                test_rule(
                    name = "{}_{}_loads_plugin_{}_{}".format(
                        name,
                        target_name,
                        mode_name,
                        mnemonic.lower(),
                    ),
                    expected_argv = [
                        "-Xfrontend -load-plugin-executable -Xfrontend",
                        "/third_party/bazel_rules/rules_swift/test/fixtures/compiler_plugin/plugin#MyPlugin",
                    ],
                    expected_inputs = [
                        "/third_party/bazel_rules/rules_swift/test/fixtures/compiler_plugin/plugin",
                        "*",
                    ],
                    mnemonic = mnemonic,
                    tags = all_tags,
                    target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:{}".format(
                        target_name,
                    ),
                )

            # Verify that an indirect consumer (depending on `direct_consumer`,
            # which does not re-export `macro_library` in `direct_modules`) does
            # NOT load the plugin executable.
            test_rule(
                name = "{}_indirect_consumer_does_not_load_plugin_{}_{}".format(
                    name,
                    mode_name,
                    mnemonic.lower(),
                ),
                expected_inputs = [
                    "-/third_party/bazel_rules/rules_swift/test/fixtures/compiler_plugin/plugin",
                    "*",
                ],
                mnemonic = mnemonic,
                not_expected_argv = [
                    "/third_party/bazel_rules/rules_swift/test/fixtures/compiler_plugin/plugin#MyPlugin",
                ],
                tags = all_tags,
                target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:indirect_consumer",
            )

            # Verify that `swift_compiler_plugin_import` with multiple
            # `module_names` joins them with commas (`#ImportedPluginA,ImportedPluginB`)
            # and passes the imported executable as an action input for both the
            # declaring library and its direct consumer.
            for imported_target_name in [
                "imported_macro_library",
                "imported_direct_consumer",
            ]:
                test_rule(
                    name = "{}_{}_loads_imported_plugin_{}_{}".format(
                        name,
                        imported_target_name,
                        mode_name,
                        mnemonic.lower(),
                    ),
                    expected_argv = [
                        "-Xfrontend -load-plugin-executable -Xfrontend third_party/bazel_rules/rules_swift/test/fixtures/compiler_plugin/fake_plugin.sh#ImportedPluginA,ImportedPluginB",
                    ],
                    expected_inputs = [
                        "third_party/bazel_rules/rules_swift/test/fixtures/compiler_plugin/fake_plugin.sh",
                        "*",
                    ],
                    mnemonic = mnemonic,
                    tags = all_tags,
                    target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:{}".format(
                        imported_target_name,
                    ),
                )

    # Verify that `swift_compiler_plugin` fails at analysis time when `srcs` is
    # empty.
    analysis_failure_test(
        name = "{}_empty_srcs_fails".format(name),
        expected_message = "A compiler plugin must have at least one file in 'srcs'.",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/compiler_plugin:empty_srcs_plugin",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

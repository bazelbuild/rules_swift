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

"""Tests for compiler plugin (macro) propagation."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)

direct_plugin_loading_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.load_plugins_from_direct_dependencies",
        ],
    },
)

def macro_plugin_test_suite(name, tags = []):
    """Test suite for compiler plugin propagation to dependents.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # The module that declares the macro loads its own plugin.
    action_command_line_test(
        name = "{}_declaring_module_loads_plugin".format(name),
        expected_argv = ["-load-plugin-executable"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/macros:stringify",
    )

    # A module that directly depends on the library declaring the macro must
    # load the plugin, since its sources may contain expansion sites.
    direct_plugin_loading_test(
        name = "{}_direct_dependent_loads_plugin".format(name),
        expected_argv = ["-load-plugin-executable"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/macros:stringify_user",
    )

    # Preserve transitive plugin loading by default for compatibility with
    # sources that use a macro through a transitive import or default argument.
    action_command_line_test(
        name = "{}_transitive_dependent_loads_plugin_by_default".format(name),
        expected_argv = ["-load-plugin-executable"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/macros:transitive_user",
    )

    # The opt-in direct-loading feature keeps the plugin executable out of
    # transitive consumers' compilation actions, preventing implementation
    # changes from invalidating the entire reverse-dependency closure.
    direct_plugin_loading_test(
        name = "{}_direct_loading_excludes_transitive_plugin".format(name),
        mnemonic = "SwiftCompile",
        not_expected_argv = ["-load-plugin-executable"],
        tags = all_tags,
        target_under_test = "//test/fixtures/macros:transitive_user",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

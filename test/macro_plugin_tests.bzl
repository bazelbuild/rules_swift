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
    action_command_line_test(
        name = "{}_direct_dependent_loads_plugin".format(name),
        expected_argv = ["-load-plugin-executable"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/macros:stringify_user",
    )

    # A module that only sees the macro-declaring module transitively must
    # not: macros are source-level transformations, so the compiler never
    # loads plugins when deserializing dependency modules. Passing the plugin
    # anyway makes its executable an input to every transitive consumer's
    # compilation, so any change to the plugin recompiles all of them.
    action_command_line_test(
        name = "{}_transitive_dependent_does_not_load_plugin".format(name),
        mnemonic = "SwiftCompile",
        not_expected_argv = ["-load-plugin-executable"],
        tags = all_tags,
        target_under_test = "//test/fixtures/macros:transitive_user",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

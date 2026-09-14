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

"""Rules for testing Swift entries in explicit module maps."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")

def _explicit_swift_module_map_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    actions = analysistest.target_actions(env)
    module_map = ctx.attr.module_map
    matching_actions = [
        action
        for action in actions
        if module_map in [file.short_path for file in action.outputs.to_list()]
    ]
    if len(matching_actions) != 1:
        unittest.fail(
            env,
            "Target '{}' expected one action producing '{}', but found {}. Outputs: {}".format(
                target_under_test.label,
                module_map,
                len(matching_actions),
                [file.short_path for action in actions for file in action.outputs.to_list()],
            ),
        )
        return analysistest.end(env)

    entries = json.decode(matching_actions[0].content)
    matching_entries = [
        entry
        for entry in entries
        if entry["moduleName"] == ctx.attr.module_name and "modulePath" in entry
    ]
    message_prefix = "In explicit module map '{}' for target '{}', ".format(
        module_map,
        target_under_test.label,
    )
    if len(matching_entries) != 1:
        unittest.fail(
            env,
            "{}expected one Swift entry for '{}', but found {}. Entries: {}".format(
                message_prefix,
                ctx.attr.module_name,
                len(matching_entries),
                entries,
            ),
        )
        return analysistest.end(env)

    entry = matching_entries[0]
    for key, expected_path in ctx.attr.expected_mapping.items():
        actual_path = entry.get(key)
        if type(actual_path) != "string" or not actual_path.endswith(expected_path):
            unittest.fail(
                env,
                "{}module '{}' expected '{}' to end with '{}', but got '{}'".format(
                    message_prefix,
                    ctx.attr.module_name,
                    key,
                    expected_path,
                    actual_path,
                ),
            )
    for key in ctx.attr.not_expected_keys:
        if key in entry:
            unittest.fail(
                env,
                "{}module '{}' should not contain '{}', but got '{}'".format(
                    message_prefix,
                    ctx.attr.module_name,
                    key,
                    entry[key],
                ),
            )

    return analysistest.end(env)

def make_explicit_swift_module_map_test_rule(config_settings = {}):
    """Returns an explicit module map analysis test with custom configs.

    Args:
        config_settings: Configuration settings to apply to the target under test.

    Returns:
        A rule that checks a Swift module's entry in a generated JSON map.
    """
    return analysistest.make(
        _explicit_swift_module_map_test_impl,
        attrs = {
            "module_map": attr.string(
                mandatory = True,
                doc = "The short path of the generated explicit module map.",
            ),
            "module_name": attr.string(
                mandatory = True,
                doc = "The Swift module whose entry should be inspected.",
            ),
            "expected_mapping": attr.string_dict(
                doc = "Expected path fields and their suffixes, excluding configuration-specific prefixes.",
            ),
            "not_expected_keys": attr.string_list(
                doc = "Fields that must be absent from the module entry.",
            ),
        },
        config_settings = config_settings,
    )

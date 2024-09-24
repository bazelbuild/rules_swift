# Copyright 2020 The Bazel Authors. All rights reserved.
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

"""Rules for testing whether or not actions are simply created by a rule."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")

visibility([
    "@build_bazel_rules_swift//test/...",
])

def _actions_created_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    actions = analysistest.target_actions(env)
    for mnemonic in ctx.attr.mnemonics:
        is_negative_test = mnemonic.startswith("-")
        if is_negative_test:
            mnemonic = mnemonic[1:]

        matching_actions = [
            action
            for action in actions
            if action.mnemonic == mnemonic
        ]
        actual_mnemonics = collections.uniq(
            [action.mnemonic for action in actions],
        )

        if is_negative_test and matching_actions:
            unittest.fail(
                env,
                ("Target '{}' registered actions with the mnemonic '{}', " +
                 "but it was not expected to (it had {}).").format(
                    str(target_under_test.label),
                    mnemonic,
                    actual_mnemonics,
                ),
            )
        elif not is_negative_test and not matching_actions:
            unittest.fail(
                env,
                ("Target '{}' registered no actions with the expected " +
                 "mnemonic '{}' (it had {}).").format(
                    str(target_under_test.label),
                    mnemonic,
                    actual_mnemonics,
                ),
            )

    return analysistest.end(env)

def make_actions_created_test_rule(config_settings = {}):
    """Returns a new `actions_created_test`-like rule with custom configs.

    Args:
        config_settings: A dictionary of configuration settings and their values
            that should be applied during tests.

    Returns:
        A rule returned by `analysistest.make` that has the
        `actions_created_test` interface and the given config settings.
    """
    return analysistest.make(
        _actions_created_test_impl,
        attrs = {
            "mnemonics": attr.string_list(
                mandatory = True,
                doc = """\
A list of mnemonics that are expected to be created by the target under test.
A mnemonic may also be preceded by a `-` to indicate that it is not expected
to be created and the test should fail if it finds one.
""",
            ),
        },
        config_settings = config_settings,
    )

# A default instantiation of the rule when no custom config settings are needed.
actions_created_test = make_actions_created_test_rule()

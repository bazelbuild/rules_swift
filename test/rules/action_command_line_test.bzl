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

"""Rules for testing the contents of action command lines."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")
load("//swift:providers.bzl", "SwiftSymbolGraphInfo", "SwiftSynthesizedInterfaceInfo")

_AspectActionInfo = provider(
    doc = "Contains actions registered on a target including by aspects.",
    fields = ["actions"],
)

def _aspect_action_retrieving_aspect_impl(target, _ctx):
    return [_AspectActionInfo(actions = target.actions)]

_aspect_action_retrieving_aspect = aspect(
    implementation = _aspect_action_retrieving_aspect_impl,
    required_aspect_providers = [
        [SwiftSymbolGraphInfo],
        [SwiftSynthesizedInterfaceInfo],
    ],
)

def _action_command_line_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    actions = (
        target_under_test[_AspectActionInfo].actions if _AspectActionInfo in target_under_test else analysistest.target_actions(env)
    )
    mnemonic = ctx.attr.mnemonic
    matching_actions = [
        action
        for action in actions
        if action.mnemonic == mnemonic
    ]
    if not matching_actions:
        actual_mnemonics = collections.uniq(
            [action.mnemonic for action in actions],
        )
        unittest.fail(
            env,
            ("Target '{}' registered no actions with the mnemonic '{}' " +
             "(it had {}).").format(
                str(target_under_test.label),
                mnemonic,
                actual_mnemonics,
            ),
        )
        return analysistest.end(env)
    if len(matching_actions) != 1:
        unittest.fail(
            env,
            ("Expected exactly one action with the mnemonic '{}', " +
             "but found {}.").format(
                mnemonic,
                len(matching_actions),
            ),
        )
        return analysistest.end(env)

    action = matching_actions[0]
    message_prefix = "In {} action for target '{}', ".format(
        mnemonic,
        str(target_under_test.label),
    )

    concatenated_args = " ".join(action.argv) + " "
    bin_dir = analysistest.target_bin_dir_path(env)
    sdk_version = None
    if hasattr(ctx.attr, "_sdk_platform"):
        xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
        sdk_version = str(xcode_config.sdk_version_for_platform(
            getattr(apple_common.platform, ctx.attr._sdk_platform),
        ))
    for expected in ctx.attr.expected_argv:
        expected = expected.replace("$(BIN_DIR)", bin_dir).replace("$(WORKSPACE_NAME)", ctx.workspace_name)
        if sdk_version:
            expected = expected.replace("$(SDK_VERSION)", sdk_version)
        if expected + " " not in concatenated_args and expected + "=" not in concatenated_args:
            unittest.fail(
                env,
                "{}expected argv to contain '{}', but it did not: {}".format(
                    message_prefix,
                    expected,
                    concatenated_args,
                ),
            )
    for not_expected in ctx.attr.not_expected_argv:
        not_expected = not_expected.replace("$(BIN_DIR)", bin_dir).replace("$(WORKSPACE_NAME)", ctx.workspace_name)
        if sdk_version:
            not_expected = not_expected.replace("$(SDK_VERSION)", sdk_version)
        if not_expected + " " in concatenated_args or not_expected + "=" in concatenated_args:
            unittest.fail(
                env,
                "{}expected argv to not contain '{}', but it did: {}".format(
                    message_prefix,
                    not_expected,
                    concatenated_args,
                ),
            )

    return analysistest.end(env)

def make_action_command_line_test_rule(config_settings = {}, extra_target_under_test_aspects = [], sdk_platform = None):
    """Returns a new `action_command_line_test`-like rule with custom configs.

    Args:
        config_settings: A dictionary of configuration settings and their values
            that should be applied during tests.
        extra_target_under_test_aspects: Aspects whose actions should be inspected.
        sdk_platform: Optional apple_common.platform field name whose SDK version
            replaces $(SDK_VERSION) in expected and unexpected arguments.

    Returns:
        A rule returned by `analysistest.make` that has the
        `action_command_line_test` interface and the given config settings.
    """
    aspects = list(extra_target_under_test_aspects)
    if aspects:
        aspects.append(_aspect_action_retrieving_aspect)

    sdk_attrs = {}
    if sdk_platform:
        sdk_attrs = {
            "_sdk_platform": attr.string(default = sdk_platform),
            "_xcode_config": attr.label(default = configuration_field(
                fragment = "apple",
                name = "xcode_config_label",
            )),
        }

    return analysistest.make(
        _action_command_line_test_impl,
        attrs = sdk_attrs | {
            "expected_argv": attr.string_list(
                mandatory = False,
                doc = """\
A list of strings representing substrings expected to appear in the action
command line, after concatenating all command line arguments into a single
space-delimited string.
""",
            ),
            "mnemonic": attr.string(
                mandatory = True,
                doc = """\
The mnemonic of the action to be inspected on the target under test. It is
expected that there will be exactly one of these.
""",
            ),
            "not_expected_argv": attr.string_list(
                mandatory = False,
                doc = """\
A list of strings representing substrings expected not to appear in the action
command line, after concatenating all command line arguments into a single
space-delimited string.
""",
            ),
        },
        fragments = ["apple"] if sdk_platform else [],
        config_settings = config_settings,
        extra_target_under_test_aspects = aspects,
    )

action_command_line_test = make_action_command_line_test_rule()

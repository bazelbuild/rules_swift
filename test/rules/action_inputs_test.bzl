"""Rules for testing action inputs contain expected files."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")

def _action_inputs_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    actions = analysistest.target_actions(env)
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

    input_paths = [input.short_path for input in action.inputs.to_list()]

    for expected_input in ctx.attr.expected_inputs:
        found = False
        for path in input_paths:
            if expected_input in path:
                found = True
                break
        if not found:
            unittest.fail(
                env,
                "{}expected inputs to contain file matching '{}', but it did not. Inputs: {}".format(
                    message_prefix,
                    expected_input,
                    input_paths,
                ),
            )

    for not_expected_input in ctx.attr.not_expected_inputs:
        found = False
        for path in input_paths:
            if not_expected_input in path:
                found = True
                break
        if found:
            unittest.fail(
                env,
                "{}expected inputs to not contain file matching '{}', but it did. Inputs: {}".format(
                    message_prefix,
                    not_expected_input,
                    input_paths,
                ),
            )

    return analysistest.end(env)

def make_action_inputs_test_rule(config_settings = {}):
    """A `action_inputs_test`-like rule with custom configs.

    Args:
        config_settings: A dictionary of configuration settings and their values
            that should be applied during tests.

    Returns:
        A rule returned by `analysistest.make` that has the `action_inputs_test`
        interface and the given config settings.
    """
    return analysistest.make(
        _action_inputs_test_impl,
        attrs = {
            "mnemonic": attr.string(
                mandatory = True,
                doc = "The mnemonic of the action to test.",
            ),
            "expected_inputs": attr.string_list(
                default = [],
                doc = "List of file patterns that should be present in action inputs.",
            ),
            "not_expected_inputs": attr.string_list(
                default = [],
                doc = "List of file patterns that should not be present in action inputs.",
            ),
        },
        config_settings = config_settings,
    )

# A default instantiation of the rule when no custom config settings are needed.
action_inputs_test = make_action_inputs_test_rule()

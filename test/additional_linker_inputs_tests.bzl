"""Tests for swift_binary's additional_linker_inputs attribute."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")

def _swift_binary_additional_linker_inputs_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    link_actions = [
        action
        for action in actions
        if action.mnemonic == "CppLink"
    ]

    if not link_actions:
        unittest.fail(
            env,
            "Expected to find a CppLink action but found none. Available actions: {}".format(
                [action.mnemonic for action in actions],
            ),
        )
        return analysistest.end(env)

    if len(link_actions) != 1:
        unittest.fail(
            env,
            "Expected exactly one CppLink action, but found {}".format(len(link_actions)),
        )
        return analysistest.end(env)

    link_action = link_actions[0]

    expected_inputs = ctx.attr.expected_additional_inputs
    expected_linkopts = ctx.attr.expected_linkopts

    action_input_paths = set([input.short_path for input in link_action.inputs.to_list()])

    if expected_inputs:
        missing_inputs = set(expected_inputs) - action_input_paths
        if missing_inputs:
            unittest.fail(
                env,
                "Missing expected additional linker inputs: {}. Available inputs: {}".format(
                    sorted(missing_inputs),
                    sorted(action_input_paths),
                ),
            )

    if expected_linkopts:
        missing_linkopts = []
        for expected_linkopt in expected_linkopts:
            # Use substring match since -Wl, options may be grouped with other flags
            found = False
            for arg in link_action.argv:
                if expected_linkopt in arg:
                    found = True
                    break
            if not found:
                missing_linkopts.append(expected_linkopt)

        if missing_linkopts:
            unittest.fail(
                env,
                "Missing expected linkopts: {}. Link arguments were: {}".format(
                    missing_linkopts,
                    link_action.argv,
                ),
            )

    return analysistest.end(env)

swift_binary_additional_linker_inputs_test = analysistest.make(
    _swift_binary_additional_linker_inputs_test_impl,
    attrs = {
        "expected_additional_inputs": attr.string_list(
        ),
        "expected_linkopts": attr.string_list(
        ),
    },
)

def additional_linker_inputs_test_suite(name, tags = []):
    all_tags = [name] + tags

    swift_binary_additional_linker_inputs_test(
        name = "{}_with_additional_inputs".format(name),
        target_under_test = "//test/fixtures/linking:bin_with_additional_linker_inputs",
        expected_additional_inputs = ["test/fixtures/linking/test_data.bin"],
        expected_linkopts = ["-Wl,-sectcreate,__TEXT,__test_section"],
        tags = all_tags,
    )

    swift_binary_additional_linker_inputs_test(
        name = "{}_without_additional_inputs".format(name),
        target_under_test = "//test/fixtures/linking:bin_without_additional_linker_inputs",
        expected_additional_inputs = [],
        expected_linkopts = [],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

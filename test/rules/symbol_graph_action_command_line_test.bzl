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

"""A rule for testing the command line of symbol graph extraction actions.

`SwiftSymbolGraphExtract` actions are registered by
`swift_symbol_graph_aspect`, not by the target the aspect is applied to, so
they are not visible to `analysistest`-based harnesses like
`action_command_line_test` (whose action-retrieving aspect is applied before
any extra aspects and therefore cannot see their actions). This rule instead
applies `swift_symbol_graph_aspect` followed by its own action-capturing
aspect, whose `required_aspect_providers` orders it after the symbol graph
aspect so that `target.actions` includes the extraction actions.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//swift:providers.bzl", "SwiftSymbolGraphInfo")
load("//swift:swift_symbol_graph_aspect.bzl", "swift_symbol_graph_aspect")

_CapturedActionsInfo = provider(
    doc = "Captures the actions registered on a target and its aspects.",
    fields = ["actions"],
)

def _captured_actions_aspect_impl(target, _aspect_ctx):
    return [_CapturedActionsInfo(actions = target.actions)]

_captured_actions_aspect = aspect(
    implementation = _captured_actions_aspect_impl,
    # Order this aspect after `swift_symbol_graph_aspect` so that
    # `target.actions` includes the actions the symbol graph aspect registers.
    required_aspect_providers = [SwiftSymbolGraphInfo],
)

def _features_transition_impl(settings, attr):
    return {
        "//command_line_option:features": (
            settings["//command_line_option:features"] + attr.features_under_test
        ),
    }

_features_transition = transition(
    implementation = _features_transition_impl,
    inputs = ["//command_line_option:features"],
    outputs = ["//command_line_option:features"],
)

def _failure_script(message):
    return "\n".join([
        "#!/usr/bin/env bash",
        "echo {} >&2".format(shell.quote("ERROR: " + message)),
        "exit 1",
        "",
    ])

def _symbol_graph_action_command_line_test_impl(ctx):
    target_under_test = ctx.attr.target_under_test[0]
    actions = target_under_test[_CapturedActionsInfo].actions
    matching_actions = [
        action
        for action in actions
        if action.mnemonic == "SwiftSymbolGraphExtract"
    ]

    script_file = ctx.actions.declare_file("{}.sh".format(ctx.label.name))
    runfiles_files = []

    if len(matching_actions) != 1:
        ctx.actions.write(
            output = script_file,
            content = _failure_script(
                ("Expected exactly one SwiftSymbolGraphExtract action on " +
                 "target '{}', but found {} (mnemonics: {}).").format(
                    str(target_under_test.label),
                    len(matching_actions),
                    [action.mnemonic for action in actions],
                ),
            ),
            is_executable = True,
        )
    else:
        # Concatenate the arguments into a single string, with a trailing
        # space, so that expected substrings can be matched as `<arg> ` or
        # `<arg>=` without matching prefixes of longer arguments (the same
        # semantics as `action_command_line_test`).
        concatenated_args = " ".join(matching_actions[0].argv) + " "
        args_file = ctx.actions.declare_file(
            "{}_args.txt".format(ctx.label.name),
        )
        ctx.actions.write(output = args_file, content = concatenated_args)
        runfiles_files.append(args_file)

        script_lines = [
            "#!/usr/bin/env bash",
            "args_file={}".format(shell.quote(args_file.short_path)),
            "failed=0",
            "function check_expected() {",
            "  if ! grep -qF -- \"$1 \" \"$args_file\" && " +
            "! grep -qF -- \"$1=\" \"$args_file\"; then",
            "    echo \"ERROR: expected argv to contain '$1', but it did " +
            "not: $(cat \"$args_file\")\" >&2",
            "    failed=1",
            "  fi",
            "}",
            "function check_not_expected() {",
            "  if grep -qF -- \"$1 \" \"$args_file\" || " +
            "grep -qF -- \"$1=\" \"$args_file\"; then",
            "    echo \"ERROR: expected argv to not contain '$1', but it " +
            "did: $(cat \"$args_file\")\" >&2",
            "    failed=1",
            "  fi",
            "}",
        ]
        for expected in ctx.attr.expected_argv:
            script_lines.append(
                "check_expected {}".format(shell.quote(expected)),
            )
        for not_expected in ctx.attr.not_expected_argv:
            script_lines.append(
                "check_not_expected {}".format(shell.quote(not_expected)),
            )
        script_lines.append("exit $failed")
        script_lines.append("")

        ctx.actions.write(
            output = script_file,
            content = "\n".join(script_lines),
            is_executable = True,
        )

    return [
        DefaultInfo(
            executable = script_file,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

symbol_graph_action_command_line_test = rule(
    attrs = {
        "expected_argv": attr.string_list(
            doc = """\
A list of strings representing substrings expected to appear in the action
command line, after concatenating all command line arguments into a single
space-delimited string.
""",
        ),
        "features_under_test": attr.string_list(
            doc = """\
Feature strings appended to `--features` in the configuration of the target
under test.
""",
        ),
        "not_expected_argv": attr.string_list(
            doc = """\
A list of strings representing substrings expected not to appear in the action
command line, after concatenating all command line arguments into a single
space-delimited string.
""",
        ),
        "target_under_test": attr.label(
            aspects = [swift_symbol_graph_aspect, _captured_actions_aspect],
            cfg = _features_transition,
            doc = "The target whose symbol graph extraction is inspected.",
            mandatory = True,
        ),
    },
    doc = """\
Tests the command line of the `SwiftSymbolGraphExtract` action registered by
`swift_symbol_graph_aspect` on the target under test, optionally under
additional feature settings.
""",
    implementation = _symbol_graph_action_command_line_test_impl,
    test = True,
)

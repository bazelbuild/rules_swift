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

"""Analysis tests for Embedded Swift compilation."""

load(
    "@bazel_skylib//lib:unittest.bzl",
    "analysistest",
    "asserts",
)

visibility("private")

def _count_subsequence(argv, subseq):
    count = 0
    subseq_len = len(subseq)
    for i in range(len(argv) - subseq_len + 1):
        if argv[i:i + subseq_len] == subseq:
            count += 1
    return count

def _embedded_compile_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    compile_actions = [a for a in actions if a.mnemonic == "SwiftCompile"]
    asserts.equals(
        env,
        1,
        len(compile_actions),
        "Expected a single monolithic SwiftCompile action for Embedded Swift.",
    )
    asserts.equals(
        env,
        0,
        len([
            a
            for a in actions
            if a.mnemonic in ("SwiftCompileModule", "SwiftCompileCodegen")
        ]),
        "Expected parallel compilation actions to be suppressed for Embedded Swift.",
    )

    if len(compile_actions) != 1:
        return analysistest.end(env)

    argv = compile_actions[0].argv
    asserts.equals(
        env,
        1,
        _count_subsequence(argv, ["-enable-experimental-feature", "Embedded"]),
        "Expected `-enable-experimental-feature Embedded` exactly once in argv: {}".format(argv),
    )
    asserts.equals(
        env,
        1,
        _count_subsequence(argv, ["-whole-module-optimization"]),
        "Expected `-whole-module-optimization` exactly once in argv: {}".format(argv),
    )
    asserts.equals(
        env,
        1,
        _count_subsequence(argv, ["-num-threads", "12"]),
        "Expected `-num-threads 12` exactly once in argv: {}".format(argv),
    )
    asserts.true(
        env,
        "-output-file-map" in argv,
        "Expected `-output-file-map` for multi-threaded WMO (preserving per-file indexstore support), got argv: {}".format(argv),
    )

    for disallowed_flag in (
        "-disable-cmo",
        "-enable-batch-mode",
    ):
        asserts.false(
            env,
            disallowed_flag in argv,
            "Expected `{}` to be omitted for Embedded Swift, got argv: {}".format(
                disallowed_flag,
                argv,
            ),
        )

    object_outputs = [
        out
        for out in compile_actions[0].outputs.to_list()
        if out.extension == "o"
    ]
    asserts.equals(
        env,
        2,
        len(object_outputs),
        "Expected per-file `.o` outputs for multi-threaded WMO Embedded Swift, got: {}".format(
            object_outputs,
        ),
    )

    return analysistest.end(env)

_embedded_experimental_feature_test = analysistest.make(
    _embedded_compile_test_impl,
)

_embedded_build_setting_test = analysistest.make(
    _embedded_compile_test_impl,
    config_settings = {
        "@build_bazel_rules_swift//swift:embedded": True,
    },
)

_embedded_both_opt_compile_test = analysistest.make(
    _embedded_compile_test_impl,
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
        "@build_bazel_rules_swift//swift:embedded": True,
    },
)

def embedded_test_suite(name):
    """Test suite for Embedded Swift compilation configuration.

    Args:
        name: The base name to be prefixed to things created by this macro.
    """
    _embedded_build_setting_test(
        name = "{}_via_build_setting_test".format(name),
        target_under_test = "@build_bazel_rules_swift//test/fixtures/embedded:dual_mode_library",
    )
    _embedded_experimental_feature_test(
        name = "{}_via_experimental_feature_test".format(name),
        target_under_test = "@build_bazel_rules_swift//test/fixtures/embedded:via_experimental_feature",
    )
    _embedded_both_opt_compile_test(
        name = "{}_via_build_setting_and_experimental_feature_opt_test".format(name),
        target_under_test = "@build_bazel_rules_swift//test/fixtures/embedded:via_experimental_feature",
    )

    native.test_suite(
        name = name,
        tests = [
            ":{}_via_build_setting_test".format(name),
            ":{}_via_experimental_feature_test".format(name),
            ":{}_via_build_setting_and_experimental_feature_opt_test".format(name),
        ],
    )

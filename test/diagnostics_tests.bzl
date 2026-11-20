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

"""Tests for serialized Swift diagnostics and aspect-based output collection."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:build_test.bzl", "build_test")

visibility("private")

_FEATURE = "swift.serialized_diagnostics_file"
_SWIFTCOPTS = str(Label("//swift:copt"))

def _diagnostics_outputs_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    outputs = []
    for action in analysistest.target_actions(env):
        diagnostics = [file for file in action.outputs.to_list() if file.extension == "dia"]
        if action.mnemonic == "SwiftCompile":
            outputs.extend(diagnostics)
            asserts.equals(env, ctx.attr.enabled, "-serialize-diagnostics" in action.argv)
        elif action.mnemonic == "SwiftDeriveFiles":
            asserts.equals(env, [], diagnostics)
            asserts.false(env, "-serialize-diagnostics" in action.argv)
    asserts.equals(env, sorted(ctx.attr.expected_files), sorted([file.short_path for file in outputs]))
    asserts.equals(env, sorted(ctx.attr.expected_directories), sorted([file.short_path for file in outputs if file.is_directory]))
    if OutputGroupInfo in target:
        asserts.false(env, hasattr(target[OutputGroupInfo], "swift_diagnostics"))
    return analysistest.end(env)

def _make_outputs_test(features = [], swiftcopts = []):
    return analysistest.make(
        _diagnostics_outputs_test_impl,
        attrs = {
            "enabled": attr.bool(default = True),
            "expected_files": attr.string_list(),
            "expected_directories": attr.string_list(),
        },
        config_settings = {
            "//command_line_option:features": features,
            _SWIFTCOPTS: swiftcopts,
        },
    )

_disabled_outputs_test = _make_outputs_test()
_outputs_test = _make_outputs_test(features = [_FEATURE])
_wmo_outputs_test = _make_outputs_test(features = [_FEATURE], swiftcopts = ["-wmo"])
_single_threaded_outputs_test = _make_outputs_test(features = [_FEATURE], swiftcopts = ["-wmo", "-num-threads", "0"])
_split_outputs_test = _make_outputs_test(features = [_FEATURE, "swift.split_derived_files_generation"])
_single_threaded_scoped_outputs_test = _make_outputs_test(
    features = [_FEATURE, "swift.add_target_name_to_output"],
    swiftcopts = ["-wmo", "-num-threads", "0"],
)

_DiagnosticsInfo = provider(
    doc = "Diagnostics collected by the test aspect.",
    fields = {"files": "The target's transitive diagnostics artifacts."},
)

def _diagnostics_aspect_impl(target, ctx):
    direct = [
        output
        for action in target.actions
        for output in action.outputs.to_list()
        if output.extension == "dia"
    ]
    transitive = [
        dep[_DiagnosticsInfo].files
        for name in ["deps", "private_deps"]
        for dep in getattr(ctx.rule.attr, name, [])
        if _DiagnosticsInfo in dep
    ]
    return [_DiagnosticsInfo(files = depset(direct, transitive = transitive))]

_diagnostics_aspect = aspect(
    implementation = _diagnostics_aspect_impl,
    attr_aspects = ["deps", "private_deps"],
)

def _diagnostics_transition_impl(_settings, attr):
    return {
        "//command_line_option:features": [_FEATURE] + attr.extra_features,
        _SWIFTCOPTS: attr.swiftcopts,
    }

_diagnostics_transition = transition(
    implementation = _diagnostics_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:features", _SWIFTCOPTS],
)

def _diagnostics_files_impl(ctx):
    transitive = [dep[_DiagnosticsInfo].files for dep in ctx.attr.deps]
    if ctx.attr.include_ast:
        transitive.extend([dep[OutputGroupInfo].swift_ast_file for dep in ctx.attr.deps])
    files = depset(transitive = transitive)
    if not files.to_list():
        fail("The aspect did not collect any serialized diagnostics outputs.")
    return [DefaultInfo(files = files)]

_diagnostics_files = rule(
    implementation = _diagnostics_files_impl,
    attrs = {
        "deps": attr.label_list(aspects = [_diagnostics_aspect], cfg = _diagnostics_transition),
        "extra_features": attr.string_list(),
        "include_ast": attr.bool(),
        "swiftcopts": attr.string_list(),
    },
)

def diagnostics_test_suite(name, tags = []):
    """Tests declared diagnostics outputs and executes the corresponding compiles.

    Args:
        name: The base name of the test targets.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags
    multiple_files = "//test/fixtures/multiple_files"
    multi_outputs = [
        "test/fixtures/multiple_files/multiple_files_objs/Empty.swift.dia",
        "test/fixtures/multiple_files/multiple_files_objs/Empty2.swift.dia",
    ]
    _disabled_outputs_test(
        name = name + "_disabled",
        enabled = False,
        target_under_test = multiple_files,
        tags = all_tags,
    )
    _outputs_test(
        name = name + "_single_source",
        expected_files = ["test/fixtures/basic/first_objs/first.swift.dia"],
        target_under_test = "//test/fixtures/basic:first",
        tags = all_tags,
    )
    _outputs_test(
        name = name + "_multiple_sources",
        expected_files = multi_outputs,
        target_under_test = multiple_files,
        tags = all_tags,
    )
    _wmo_outputs_test(
        name = name + "_wmo",
        expected_files = ["test/fixtures/multiple_files/multiple_files.dia"],
        target_under_test = multiple_files,
        tags = all_tags,
    )
    _single_threaded_outputs_test(
        name = name + "_wmo_single_threaded",
        expected_files = ["test/fixtures/multiple_files/multiple_files.dia"],
        target_under_test = multiple_files,
        tags = all_tags,
    )
    _single_threaded_scoped_outputs_test(
        name = name + "_wmo_single_threaded_target_scoped",
        expected_files = ["test/fixtures/multiple_files/multiple_files.dia"],
        target_under_test = multiple_files,
        tags = all_tags,
    )
    _split_outputs_test(
        name = name + "_split_derived_files",
        expected_files = multi_outputs,
        target_under_test = multiple_files,
        tags = all_tags,
    )
    tree_output = "test/fixtures/tree_artifacts/with_tree_artifact_and_static_objs/dynamic_sources.swift.dia"
    _outputs_test(
        name = name + "_tree_artifact",
        expected_files = [
            tree_output,
            "test/fixtures/tree_artifacts/with_tree_artifact_and_static_objs/Static.swift.dia",
        ],
        expected_directories = [tree_output],
        target_under_test = "//test/fixtures/tree_artifacts:with_tree_artifact_and_static",
        tags = all_tags,
    )

    # Request the artifacts through an aspect so these tests execute the compile
    # actions and catch declared outputs that the compiler does not actually emit.
    for suffix, swiftcopts, extra_features in [
        ("incremental", [], []),
        ("wmo", ["-wmo"], []),
        ("single_threaded", ["-wmo", "-num-threads", "0"], []),
        ("single_threaded_target_scoped", ["-wmo", "-num-threads", "0"], ["swift.add_target_name_to_output"]),
        ("split", [], ["swift.split_derived_files_generation"]),
    ]:
        files_target = name + "_" + suffix + "_files"
        _diagnostics_files(
            name = files_target,
            deps = [
                "//test/fixtures/basic:second",
                multiple_files,
                "//test/fixtures/tree_artifacts:with_tree_artifact_and_static",
            ],
            extra_features = extra_features,
            swiftcopts = swiftcopts,
            tags = ["manual"],
        )
        build_test(
            name = name + "_" + suffix + "_build_test",
            targets = [files_target],
            tags = all_tags,
        )
    ast_files_target = name + "_single_threaded_ast_files"
    _diagnostics_files(
        name = ast_files_target,
        deps = ["//test/fixtures/basic:first"],
        include_ast = True,
        swiftcopts = ["-wmo", "-num-threads", "0"],
        tags = ["manual"],
    )
    build_test(
        name = name + "_single_threaded_ast_build_test",
        targets = [ast_files_target],
        tags = all_tags,
    )
    native.test_suite(name = name, tags = all_tags)

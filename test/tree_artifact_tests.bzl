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

"""Tests for tree artifact support in srcs."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:build_test.bzl", "build_test")

visibility("private")

def _actions_created_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    asserts.true(env, any([action.mnemonic == "SwiftCompile" for action in actions]))
    return analysistest.end(env)

actions_created_test = analysistest.make(_actions_created_test_impl)

opt_actions_create_test = analysistest.make(
    _actions_created_test_impl,
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
    },
)

def tree_artifact_test_suite(name, tags = []):
    """Test suite for tree artifact support in srcs.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that a target with only a tree artifact in srcs registers
    # a Swift compilation action successfully.
    actions_created_test(
        name = "{}_tree_artifact_only".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifacts:with_tree_artifact",
    )

    # Verify that a target with both static files and a tree artifact in srcs
    # registers a Swift compilation action successfully.
    actions_created_test(
        name = "{}_tree_artifact_and_static".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifacts:with_tree_artifact_and_static",
    )

    # Verify that a target with a tree artifact and WMO enabled registers
    # a Swift compilation action.
    actions_created_test(
        name = "{}_tree_artifact_wmo".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifacts:with_tree_artifact_wmo",
    )

    # Verify that optimized WMO with tree artifacts registers a SwiftCompile action.
    opt_actions_create_test(
        name = "{}_tree_artifact_opt_wmo".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/tree_artifacts:with_tree_artifact_wmo",
    )

    # The tests above verify that the expected actions are created, but don't
    # execute the actions. These build tests ensure that they execute successfully.
    build_test(
        name = "{}_build_test".format(name),
        targets = [
            "//test/fixtures/tree_artifacts:with_tree_artifact",
            "//test/fixtures/tree_artifacts:with_tree_artifact_and_static",
            "//test/fixtures/tree_artifacts:with_tree_artifact_wmo",
        ],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

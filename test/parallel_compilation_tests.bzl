# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Tests for parallel compilation."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "@build_bazel_rules_swift//test/rules:actions_created_test.bzl",
    "actions_created_test",
    "make_actions_created_test_rule",
)

visibility("private")

opt_actions_create_test = make_actions_created_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
    },
)

opt_via_swiftcopt_actions_create_test = make_actions_created_test_rule(
    config_settings = {
        "@build_bazel_rules_swift//swift:copt": ["-O"],
    },
)

def parallel_compilation_test_suite(name, tags = []):
    """Test suite for parallel compilation.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Non-optimized, non-WMO can be compiled in parallel.
    actions_created_test(
        name = "{}_no_opt_no_wmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
    )

    # Non-optimized, with-WMO can be compiled in parallel.
    actions_created_test(
        name = "{}_no_opt_with_wmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
    )

    # Optimized, non-WMO can be compiled in parallel.
    actions_created_test(
        name = "{}_with_opt_no_wmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_no_wmo",
    )

    # Optimized, with-WMO can be compiled in parallel if CMO is also disabled.
    actions_created_test(
        name = "{}_with_opt_with_wmo_no_cmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_no_cmo",
    )

    # Optimized, with-WMO cannot be compiled in parallel if CMO is enabled.
    actions_created_test(
        name = "{}_with_opt_with_wmo_with_cmo".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_cmo",
    )

    # Force `-c opt` on a non-optimized, with-WMO target and make sure we don't
    # plan parallel compilation there.
    opt_actions_create_test(
        name = "{}_no_opt_with_wmo_but_compilation_mode_opt".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
    )

    # Force `-O` using the `copt` flag on a non-optimized, with-WMO target and
    # make sure we don't plan parallel compilation there.
    opt_via_swiftcopt_actions_create_test(
        name = "{}_no_opt_with_wmo_but_swiftcopt_dash_O".format(name),
        mnemonics = ["-SwiftCompileModule", "-SwiftCompileCodegen", "SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
    )

    # Optimized, with-WMO can be compiled in parallel if library evolution is
    # enabled (which implicitly disables CMO).
    actions_created_test(
        name = "{}_with_opt_with_wmo_with_library_evolution".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_library_evolution",
    )

    # Make sure that when we look for optimizer flags, we don't treat `-Onone`
    # as being optimized.
    actions_created_test(
        name = "{}_onone_with_wmo".format(name),
        mnemonics = ["SwiftCompileModule", "SwiftCompileCodegen", "-SwiftCompile"],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/parallel_compilation:onone_with_wmo",
    )

    # The analysis tests verify that we register the actions we expect. Use a
    # `build_test` to make sure the actions execute successfully.
    build_test(
        name = "{}_build_test".format(name),
        targets = [
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_no_wmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:no_opt_with_wmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_no_wmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_no_cmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_cmo",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:with_opt_with_wmo_with_library_evolution",
            "@build_bazel_rules_swift//test/fixtures/parallel_compilation:onone_with_wmo",
        ],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

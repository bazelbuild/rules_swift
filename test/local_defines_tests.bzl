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

"""Tests for `local_defines` attribute."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//swift:providers.bzl", "SwiftInfo")
load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
)
load(
    "//test/rules:provider_test.bzl",
    "provider_test",
)

def _swift_info_defines_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.equals(
        env,
        ctx.attr.expected_defines,
        [
            define
            for module in target[SwiftInfo].direct_modules
            for define in module.swift.defines
        ],
    )
    return analysistest.end(env)

_swift_info_defines_test = analysistest.make(
    _swift_info_defines_test_impl,
    attrs = {"expected_defines": attr.string_list()},
)

def local_defines_test_suite(name, tags = []):
    """Test suite for `local_defines` attribute.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that local_defines and defines are present in the target's command line.
    action_command_line_test(
        name = "{}_target_has_defines".format(name),
        expected_argv = ["-DLOCAL_FOO", "-DPROPAGATED_BAR"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:lib_with_local_defines",
    )

    # Verify that only defines (not local_defines) are present in the dependent's command line.
    action_command_line_test(
        name = "{}_dependent_has_only_propagated_defines".format(name),
        expected_argv = ["-DPROPAGATED_BAR"],
        not_expected_argv = ["-DLOCAL_FOO"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:lib_dependent",
    )

    # Verify that local_defines are present in swift_binary command line.
    action_command_line_test(
        name = "{}_binary_has_local_defines".format(name),
        expected_argv = ["-DBIN_LOCAL_FOO"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:bin_with_local_defines",
    )

    # Verify that local_defines are present in swift_test command line.
    action_command_line_test(
        name = "{}_test_has_local_defines".format(name),
        expected_argv = ["-DTEST_LOCAL_FOO"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:test_with_local_defines",
    )

    action_command_line_test(
        name = "{}_plugin_has_local_defines".format(name),
        expected_argv = ["-DPLUGIN_LOCAL_FOO"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:plugin_with_local_defines",
    )

    _swift_info_defines_test(
        name = "{}_swift_info_does_not_propagate_local_defines".format(name),
        expected_defines = ["PROPAGATED_BAR"],
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:lib_with_local_defines",
    )

    # Verify that local_defines are present in the target's CcInfo compilation context,
    # and that propagated defines are also present but NOT local ones in the transitive
    # defines depset.
    provider_test(
        name = "{}_cc_info_defines".format(name),
        field = "compilation_context.defines!",
        expected_values = ["PROPAGATED_BAR", "-LOCAL_FOO"],
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:lib_with_local_defines",
    )

    provider_test(
        name = "{}_cc_info_local_defines".format(name),
        field = "compilation_context.local_defines!",
        expected_values = ["LOCAL_FOO"],
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:lib_with_local_defines",
    )

    # Verify that the dependent target has the propagated defines but NOT the
    # local ones in its CcInfo.
    provider_test(
        name = "{}_dependent_cc_info_defines".format(name),
        field = "compilation_context.defines!",
        expected_values = ["PROPAGATED_BAR", "-LOCAL_FOO"],
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:lib_dependent",
    )

    provider_test(
        name = "{}_dependent_cc_info_local_defines".format(name),
        field = "compilation_context.local_defines!",
        expected_values = ["-LOCAL_FOO", "-PROPAGATED_BAR"],
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:lib_dependent",
    )

    # Verify that local_defines are present in the binary target's CcInfo compilation context.
    provider_test(
        name = "{}_binary_cc_info_defines".format(name),
        field = "cc_info.compilation_context.defines!",
        expected_values = ["-BIN_LOCAL_FOO"],
        provider = "SwiftBinaryInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:bin_with_local_defines",
    )

    provider_test(
        name = "{}_binary_cc_info_local_defines".format(name),
        field = "cc_info.compilation_context.local_defines!",
        expected_values = ["BIN_LOCAL_FOO"],
        provider = "SwiftBinaryInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:bin_with_local_defines",
    )

    # Mixed language tests - These are all forced to macOS because of the ObjcCompile step.
    action_command_line_test(
        target_compatible_with = ["@platforms//os:macos"],
        name = "{}_mixed_target_has_defines_swift".format(name),
        expected_argv = ["-DLOCAL_FOO", "-DPROPAGATED_BAR"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:mixed_lib_with_local_defines",
    )

    action_command_line_test(
        target_compatible_with = ["@platforms//os:macos"],
        name = "{}_mixed_target_has_defines_objc".format(name),
        expected_argv = ["-DLOCAL_FOO", "-DPROPAGATED_BAR"],
        mnemonic = "ObjcCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:mixed_lib_with_local_defines",
    )

    action_command_line_test(
        target_compatible_with = ["@platforms//os:macos"],
        name = "{}_mixed_dependent_has_only_propagated_defines_swift".format(name),
        expected_argv = ["-DPROPAGATED_BAR"],
        not_expected_argv = ["-DLOCAL_FOO"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:mixed_lib_dependent",
    )

    action_command_line_test(
        target_compatible_with = ["@platforms//os:macos"],
        name = "{}_mixed_dependent_has_only_propagated_defines_objc".format(name),
        expected_argv = ["-DPROPAGATED_BAR"],
        not_expected_argv = ["-DLOCAL_FOO"],
        mnemonic = "ObjcCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:mixed_lib_dependent",
    )

    provider_test(
        target_compatible_with = ["@platforms//os:macos"],
        name = "{}_mixed_cc_info_defines".format(name),
        field = "compilation_context.defines!",
        expected_values = ["PROPAGATED_BAR", "-LOCAL_FOO"],
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:mixed_lib_with_local_defines",
    )

    provider_test(
        target_compatible_with = ["@platforms//os:macos"],
        name = "{}_mixed_cc_info_local_defines".format(name),
        field = "compilation_context.local_defines!",
        expected_values = ["LOCAL_FOO"],
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:mixed_lib_with_local_defines",
    )

    provider_test(
        target_compatible_with = ["@platforms//os:macos"],
        name = "{}_mixed_dependent_cc_info_defines".format(name),
        field = "compilation_context.defines!",
        expected_values = ["PROPAGATED_BAR", "-LOCAL_FOO"],
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:mixed_lib_dependent",
    )

    provider_test(
        target_compatible_with = ["@platforms//os:macos"],
        name = "{}_mixed_dependent_cc_info_local_defines".format(name),
        field = "compilation_context.local_defines!",
        expected_values = ["-LOCAL_FOO"],
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/local_defines:mixed_lib_dependent",
    )

    build_test(
        name = "{}_mixed_build_test".format(name),
        targets = ["//test/fixtures/local_defines:mixed_lib_dependent"],
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

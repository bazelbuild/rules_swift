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

"""Tests for Swift Link-Time Optimization (LTO) feature flags."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

visibility("private")

_default_fastbuild_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "fastbuild",
    },
)

_lto_full_fastbuild_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "fastbuild",
        "//command_line_option:features": ["swift.lto_full"],
    },
)

_lto_thin_fastbuild_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "fastbuild",
        "//command_line_option:features": ["swift.lto_thin"],
    },
)

_lto_both_fastbuild_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "fastbuild",
        "//command_line_option:features": [
            "swift.lto_full",
            "swift.lto_thin",
        ],
    },
)

_lto_full_opt_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
        "//command_line_option:features": [
            "-swift.compile_in_parallel",
            "swift.lto_full",
        ],
    },
)

_lto_thin_opt_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
        "//command_line_option:features": [
            "-swift.compile_in_parallel",
            "swift.lto_thin",
        ],
    },
)

_lto_both_opt_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
        "//command_line_option:features": [
            "-swift.compile_in_parallel",
            "swift.lto_full",
            "swift.lto_thin",
        ],
    },
)

def lto_test_suite(name, tags = []):
    """Test suite for `swift.lto_full` and `swift.lto_thin`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags
    target = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple"

    _default_fastbuild_test(
        name = "{}_default_no_lto".format(name),
        mnemonic = "SwiftCompileCodegen",
        not_expected_argv = [
            "-lto=llvm-full",
            "-lto=llvm-thin",
        ],
        tags = all_tags,
        target_under_test = target,
    )

    _lto_full_fastbuild_test(
        name = "{}_full_parallel_codegen".format(name),
        expected_argv = ["-lto=llvm-full"],
        mnemonic = "SwiftCompileCodegen",
        not_expected_argv = ["-lto=llvm-thin"],
        tags = all_tags,
        target_under_test = target,
    )

    _lto_full_fastbuild_test(
        name = "{}_full_parallel_module".format(name),
        expected_argv = ["-lto=llvm-full"],
        mnemonic = "SwiftCompileModule",
        not_expected_argv = ["-lto=llvm-thin"],
        tags = all_tags,
        target_under_test = target,
    )

    _lto_thin_fastbuild_test(
        name = "{}_thin_parallel_codegen".format(name),
        expected_argv = ["-lto=llvm-thin"],
        mnemonic = "SwiftCompileCodegen",
        not_expected_argv = ["-lto=llvm-full"],
        tags = all_tags,
        target_under_test = target,
    )

    _lto_both_fastbuild_test(
        name = "{}_thin_overrides_full_parallel".format(name),
        expected_argv = ["-lto=llvm-thin"],
        mnemonic = "SwiftCompileCodegen",
        not_expected_argv = ["-lto=llvm-full"],
        tags = all_tags,
        target_under_test = target,
    )

    _lto_full_opt_test(
        name = "{}_full_opt".format(name),
        expected_argv = ["-lto=llvm-full"],
        mnemonic = "SwiftCompile",
        not_expected_argv = ["-lto=llvm-thin"],
        tags = all_tags,
        target_under_test = target,
    )

    _lto_thin_opt_test(
        name = "{}_thin_opt".format(name),
        expected_argv = ["-lto=llvm-thin"],
        mnemonic = "SwiftCompile",
        not_expected_argv = ["-lto=llvm-full"],
        tags = all_tags,
        target_under_test = target,
    )

    _lto_both_opt_test(
        name = "{}_thin_overrides_full_opt".format(name),
        expected_argv = ["-lto=llvm-thin"],
        mnemonic = "SwiftCompile",
        not_expected_argv = ["-lto=llvm-full"],
        tags = all_tags,
        target_under_test = target,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

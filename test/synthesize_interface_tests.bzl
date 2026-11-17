# Copyright 2022 The Bazel Authors. All rights reserved.
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

"""Tests for synthesizing Swift interfaces for modules."""

load("//swift:swift_synthesize_interface_aspect.bzl", "swift_synthesize_interface_aspect")
load("//test/rules:action_command_line_test.bzl", "make_action_command_line_test_rule")
load(
    "//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

ios_simulator_synthesize_interface_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:platforms": [
            str(Label("@apple_support//platforms:ios_sim_arm64")),
        ],
        "//command_line_option:ios_sdk_version": "18.4",
        "//command_line_option:ios_minimum_os": "16.0",
        "//command_line_option:macos_sdk_version": "15.3",
    },
    extra_target_under_test_aspects = [
        swift_synthesize_interface_aspect,
    ],
)

def synthesize_interface_test_suite(name, tags = []):
    """Test suite for synthesizing Swift interfaces for modules.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that the `swift_extract_symbol_graph` rule produces a directory
    # output containing the correct files when the requested target is a leaf
    # module.
    provider_test(
        name = "{}_expected_files".format(name),
        expected_files = [
            "test/fixtures/synthesize_interface/c_module.synthesized.swift",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/synthesize_interface:synthesized_interface",
    )

    # Verify that interface synthesis receives the versioned prebuilt module
    # search path to avoid recompiling SDK interfaces.
    ios_simulator_synthesize_interface_test(
        name = "{}_versioned_prebuilt_module_search_path".format(name),
        expected_argv = [
            "-I__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains/XcodeDefault.xctoolchain/" +
            "usr/lib/swift/iphonesimulator/prebuilt-modules/18.4",
        ],
        mnemonic = "SwiftSynthesizeInterface",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/synthesize_interface:c_module",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

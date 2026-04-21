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

"""Tests for minimum_os_version compiler arguments."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

minimum_os_version_test = make_action_command_line_test_rule()

def _minimum_os_version_action_test(*, name, target_under_test, mnemonic = "SwiftCompile", tags = []):
    minimum_os_version_test(
        name = name,
        expected_argv = [
            "-target",
            "apple-macos99.0",
        ],
        mnemonic = mnemonic,
        tags = tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = target_under_test,
    )

def minimum_os_version_test_suite(name, tags = []):
    """Test suite for minimum_os_version compiler arguments.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    _minimum_os_version_action_test(
        name = "{}_swift_library_target_triple".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:library",
    )

    _minimum_os_version_action_test(
        name = "{}_swift_binary_target_triple".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:binary",
    )

    _minimum_os_version_action_test(
        name = "{}_swift_compiler_plugin_target_triple".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:compiler_plugin",
    )

    _minimum_os_version_action_test(
        name = "{}_swift_test_target_triple".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:test",
    )

    _minimum_os_version_action_test(
        name = "{}_swift_proto_library_target_triple".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/minimum_os_version:message_swift_proto",
    )

    build_test(
        name = "{}_swift_proto_library_group_without_attr".format(name),
        tags = all_tags,
        targets = [
            "//test/fixtures/minimum_os_version:message_swift_proto_group",
        ],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

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

"""Tests for Swift module aliases using the `:module_mapping` flag."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "//swift:swift_module_mapping_test.bzl",
    "swift_module_mapping_test",
)
load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

module_file_test = make_action_command_line_test_rule(
    config_settings = {
        str(Label("//swift:module_mapping")): str(Label("//test/fixtures/module_mapping:MySDK_module_mapping")),
        "//command_line_option:features": [
            "-swift.use_explicit_swift_module_map",
            "swift.split_derived_files_generation",
        ],
    },
)

def module_mapping_test_suite(name, tags = []):
    """Tests for Swift module aliases using the `:module_mapping` flag.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Use the physical module name when passing dependency files to both
    # compilation actions, while preserving aliases used by source imports.
    for suffix, mnemonic in [("compile", "SwiftCompile"), ("derive", "SwiftDeriveFiles")]:
        module_file_test(
            name = "{}_{}_module_file".format(name, suffix),
            expected_argv = [
                "-module-alias Common=MySDKInternal_Common",
                "-Xfrontend -swift-module-file=MySDKInternal_Common=$(BIN_DIR)/test/fixtures/module_mapping/MySDKInternal_Common.swiftmodule",
            ],
            not_expected_argv = [
                "-I$(BIN_DIR)/test/fixtures/module_mapping",
                "-swift-module-file=Common",
            ],
            mnemonic = mnemonic,
            tags = all_tags,
            target_under_test = "//test/fixtures/module_mapping:MySDK",
        )

    # Verify that a `swift_binary` builds properly when depending on a
    # `swift_import` target that references a `.swiftinterface` file.
    build_test(
        name = "{}_module_mapping_is_applied".format(name),
        targets = [
            "//test/fixtures/module_mapping:MySDK_with_mapping",
        ],
        tags = all_tags,
    )

    # Verify that a `swift_module_mapping_test` with a complete mapping
    # succeeds.
    swift_module_mapping_test(
        name = "{}_module_mapping_test_succeeds_with_complete_mapping".format(name),
        mapping = "//test/fixtures/module_mapping:ExistingLibrary_module_mapping_complete",
        tags = all_tags,
        deps = [
            "//test/fixtures/module_mapping:ExistingLibrary",
        ],
    )

    # Verify that a `swift_module_mapping_test` with an incomplete mapping
    # succeeds if the missing modules are listed in `exclude`.
    swift_module_mapping_test(
        name = "{}_module_mapping_test_succeeds_with_exclusions".format(name),
        exclude = ["NewDependency"],
        mapping = "//test/fixtures/module_mapping:ExistingLibrary_module_mapping_incomplete",
        tags = all_tags,
        deps = [
            "//test/fixtures/module_mapping:ExistingLibrary",
        ],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

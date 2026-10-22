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

"""Tests for package module interface outputs."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)
load(
    "//test/rules:provider_test.bzl",
    "make_provider_test_rule",
    "provider_test",
)

split_package_interface_action_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

split_package_interface_provider_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

package_interface_action_with_target_name_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.add_target_name_to_output",
        ],
    },
)

package_interface_provider_with_target_name_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.add_target_name_to_output",
        ],
    },
)

def package_interface_test_suite(name, tags = []):
    """Test suite for package module interface outputs.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that the `.package.swiftinterface` file is an output of the rule
    # when `library_evolution` is true and `package_name` is set.
    provider_test(
        name = "{}_swift_library_emits_package_swiftinterface".format(name),
        expected_files = [
            "test/fixtures/package_interface/PackageLibrary.package.swiftinterface",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    # Verify that the `.package.swiftinterface` file is propagated in `SwiftInfo`.
    provider_test(
        name = "{}_library_swift_info".format(name),
        expected_files = [
            "test/fixtures/package_interface/PackageLibrary.package.swiftinterface",
        ],
        field = "direct_modules.swift!.package_swiftinterface",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    # Verify that the package name and interface output path are passed to
    # the compile action.
    action_command_line_test(
        name = "{}_library_command_line".format(name),
        expected_argv = [
            "-package-name ExamplePackage",
            "-emit-package-module-interface-path $(BIN_DIR)/test/fixtures/package_interface/PackageLibrary.package.swiftinterface",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    # Verify that the `.package.swiftinterface` file is an output of the rule
    # when derived files are generated separately.
    split_package_interface_provider_test(
        name = "{}_split_default_outputs".format(name),
        expected_files = [
            "test/fixtures/package_interface/PackageLibrary.package.swiftinterface",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    # Verify that the `.package.swiftinterface` file is propagated in `SwiftInfo`
    # when derived files are generated separately.
    split_package_interface_provider_test(
        name = "{}_split_swift_info".format(name),
        expected_files = [
            "test/fixtures/package_interface/PackageLibrary.package.swiftinterface",
        ],
        field = "direct_modules.swift!.package_swiftinterface",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    # Verify that the package name and interface output path are passed to
    # the derived-files action when derived files are generated separately.
    split_package_interface_action_test(
        name = "{}_split_command_line".format(name),
        expected_argv = [
            "-package-name ExamplePackage",
            "-emit-package-module-interface-path $(BIN_DIR)/test/fixtures/package_interface/PackageLibrary.package.swiftinterface",
        ],
        mnemonic = "SwiftDeriveFiles",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    # Verify that the package interface output path includes the target name
    # when `swift.add_target_name_to_output` is enabled.
    package_interface_provider_with_target_name_test(
        name = "{}_swift_library_emits_package_swiftinterface_with_target_name".format(name),
        expected_files = [
            "test/fixtures/package_interface/package_swiftinterface_library/PackageLibrary.package.swiftinterface",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    # Verify that `SwiftInfo` contains the package interface path with the target
    # name when `swift.add_target_name_to_output` is enabled.
    package_interface_provider_with_target_name_test(
        name = "{}_library_swift_info_with_target_name".format(name),
        expected_files = [
            "test/fixtures/package_interface/package_swiftinterface_library/PackageLibrary.package.swiftinterface",
        ],
        field = "direct_modules.swift!.package_swiftinterface",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    # Verify that the compile action uses the package interface path with the
    # target name when `swift.add_target_name_to_output` is enabled.
    package_interface_action_with_target_name_test(
        name = "{}_library_command_line_with_target_name".format(name),
        expected_argv = [
            "-package-name ExamplePackage",
            "-emit-package-module-interface-path $(BIN_DIR)/test/fixtures/package_interface/package_swiftinterface_library/PackageLibrary.package.swiftinterface",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/package_interface:package_swiftinterface_library",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

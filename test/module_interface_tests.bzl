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

"""Tests for interoperability with `cc_library`-specific features."""

load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)
load(
    "@bazel_skylib//rules:build_test.bzl",
    "build_test",
)

def module_interface_test_suite(name, tags = []):
    """Test suite for features that compile Swift module interfaces.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that a `swift_binary` builds properly when depending on a
    # `swift_import` target that references a `.swiftinterface` file.
    build_test(
        name = "{}_swift_binary_imports_swiftinterface".format(name),
        targets = [
            "@build_bazel_rules_swift//test/fixtures/module_interface:client",
        ],
        tags = all_tags,
    )

    # Verify that `.swiftinterface` file is emitted when the `library_evolution`
    # attribute is true.
    provider_test(
        name = "{}_swift_library_with_evolution_emits_swiftinterface".format(name),
        expected_files = [
            "test/fixtures/module_interface/library/ToyModule.swiftinterface",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/module_interface/library:toy_module_library",
    )

    # Verify that `.swiftinterface` file is not emitted when the
    # `library_evolution` attribute is false.
    provider_test(
        name = "{}_swift_library_without_evolution_emits_no_swiftinterface".format(name),
        expected_files = [
            "-test/fixtures/module_interface/library/ToyModuleNoEvolution.swiftinterface",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/module_interface/library:toy_module_library_without_library_evolution",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

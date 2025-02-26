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

load(
    "//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

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

    native.test_suite(
        name = name,
        tags = all_tags,
    )

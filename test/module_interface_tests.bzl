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
    "@bazel_skylib//rules:build_test.bzl",
    "build_test",
)

def module_interface_test_suite(name):
    """Test suite for features that compile Swift module interfaces.

    Args:
        name: The base name to be used in targets created by this macro.
    """

    # Verify that a `swift_binary` builds properly when depending on a
    # `swift_import` target that references a `.swiftinterface` file.
    build_test(
        name = "{}_swift_binary_imports_swiftinterface".format(name),
        targets = [
            "@build_bazel_rules_swift//test/fixtures/module_interface:client",
        ],
        tags = [name],
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

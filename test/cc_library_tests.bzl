# Copyright 2021 The Bazel Authors. All rights reserved.
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

def cc_library_test_suite(name):
    """Test suite for interoperability with `cc_library`-specific features."""

    # Verify that Swift can import a `cc_library` that uses `include_prefix`,
    # `strip_include_prefix`, or both.
    build_test(
        name = "{}_swift_imports_cc_library_with_include_prefix_manipulation".format(name),
        targets = [
            "@build_bazel_rules_swift//test/fixtures/cc_library:import_prefix_and_strip_prefix",
            "@build_bazel_rules_swift//test/fixtures/cc_library:import_prefix_only",
            "@build_bazel_rules_swift//test/fixtures/cc_library:import_strip_prefix_only",
        ],
        tags = [name],
    )

    # Verify that `swift_interop_hint.exclude_hdrs` correctly excludes headers
    # from a `cc_library` that uses `include_prefix` and/or
    # `strip_include_prefix` (i.e., both the real header and the virtual header
    # are excluded).
    build_test(
        name = "{}_swift_interop_hint_excludes_headers_with_include_prefix_manipulation".format(name),
        targets = [
            "@build_bazel_rules_swift//test/fixtures/cc_library:import_prefix_and_strip_prefix_with_exclusion",
        ],
        tags = [name],
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

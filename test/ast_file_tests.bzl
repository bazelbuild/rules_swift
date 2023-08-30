# Copyright 2020 The Bazel Authors. All rights reserved.
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

"""Tests for `ast_file`."""

load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

def ast_file_test_suite(name):
    """Test suite for `swift_library` dumping ast files.

    Args:
      name: the base name to be used in things created by this macro
    """

    provider_test(
        name = "{}_with_no_deps".format(name),
        expected_files = [
            "test/fixtures/swift_through_non_swift/lower_objs/Empty.swift.ast",
        ],
        field = "swift_ast_file",
        provider = "OutputGroupInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_through_non_swift:lower",
    )

    provider_test(
        name = "{}_with_deps".format(name),
        expected_files = [
            "test/fixtures/swift_through_non_swift/upper_objs/Empty.swift.ast",
        ],
        field = "swift_ast_file",
        provider = "OutputGroupInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/swift_through_non_swift:upper",
    )

    provider_test(
        name = "{}_with_private_swift_deps".format(name),
        expected_files = [
            "test/fixtures/private_deps/client_swift_deps_objs/Empty.swift.ast",
        ],
        field = "swift_ast_file",
        provider = "OutputGroupInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/private_deps:client_swift_deps",
    )

    provider_test(
        name = "{}_with_private_cc_deps".format(name),
        expected_files = [
            "test/fixtures/private_deps/client_cc_deps_objs/Empty.swift.ast",
        ],
        field = "swift_ast_file",
        provider = "OutputGroupInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/private_deps:client_cc_deps",
    )

    provider_test(
        name = "{}_with_multiple_swift_files".format(name),
        expected_files = [
            "test/fixtures/multiple_files/multiple_files_objs/Empty.swift.ast",
            "test/fixtures/multiple_files/multiple_files_objs/Empty2.swift.ast",
        ],
        field = "swift_ast_file",
        provider = "OutputGroupInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/multiple_files",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

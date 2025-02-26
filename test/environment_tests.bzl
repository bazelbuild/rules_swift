# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""Tests for environment attributes on `swift_{binary,test}."""

load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

def environment_test_suite(name, tags = []):
    """Test suite for environment attributes on `swift_{binary,test}`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    provider_test(
        name = "{}_binary_environment_is_set".format(name),
        expected_values = [
            "TEST_ENV_VAR=test-value",
        ],
        field = "environment",
        provider = "RunEnvironmentInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/environment:binary",
    )

    provider_test(
        name = "{}_test_environment_is_set".format(name),
        expected_values = [
            "TEST_ENV_VAR=test-value",
            "*",  # Will include TEST_BINARIES_FOR_LLVM_COV
        ],
        field = "environment",
        provider = "RunEnvironmentInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/environment:test",
    )

    provider_test(
        name = "{}_test_env_inherit_is_set".format(name),
        expected_values = [
            "HOME",
        ],
        field = "inherited_environment",
        provider = "RunEnvironmentInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/environment:test",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

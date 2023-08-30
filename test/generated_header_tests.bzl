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

"""Tests for `swift_library.generated_header`."""

load(
    "@build_bazel_rules_swift//test/rules:analysis_failure_test.bzl",
    "analysis_failure_test",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

def generated_header_test_suite(name):
    """Test suite for `swift_library` generated headers.

    Args:
      name: the base name to be used in things created by this macro
    """

    # Verify that the generated header by default gets an automatically
    # generated name and is an output of the rule.
    provider_test(
        name = "{}_automatically_named_header_is_rule_output".format(name),
        expected_files = [
            "test/fixtures/generated_header/auto_header-Swift.h",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:auto_header",
    )

    # Verify that no generated header is created if the target doesn't request
    # it.
    provider_test(
        name = "{}_no_header".format(name),
        expected_files = [
            "-test/fixtures/generated_header/no_header-Swift.h",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:no_header",
    )

    # Verify that the explicit generated header is an output of the rule and
    # that the automatically named one is *not*.
    provider_test(
        name = "{}_explicit_header".format(name),
        expected_files = [
            "test/fixtures/generated_header/SomeOtherName.h",
            "-test/fixtures/generated_header/explicit_header-Swift.h",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:explicit_header",
    )

    # Verify that the build fails to analyze if an invalid extension is used.
    analysis_failure_test(
        name = "{}_invalid_extension".format(name),
        expected_message = "The generated header for a Swift module must have a '.h' extension",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:invalid_extension",
    )

    # Verify that the build analyzes if a path separator is used.
    provider_test(
        name = "{}_valid_path_separator".format(name),
        expected_files = [
            "test/fixtures/generated_header/Valid/Separator.h",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:valid_path_separator",
    )

    # Verify that the build fails if `generated_header_name` is set when
    # `generates_header` is False.
    analysis_failure_test(
        name = "{}_fails_when_name_provided_but_generates_header_is_false".format(name),
        expected_message = "'generated_header_name' may only be provided when 'generates_header' is True",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:invalid_attribute_combination",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

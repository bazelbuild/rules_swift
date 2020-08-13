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
    "make_analysis_failure_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "make_provider_test_rule",
)

# A configuration that forces header and module map generation, regardless of
# the toolchain's default feature set.
GENERATE_HEADER_AND_MODULE_MAP_CONFIG_SETTINGS = {
    "//command_line_option:features": [
        "-swift.no_generated_header",
        "-swift.no_generated_module_map",
    ],
}

# A configuration that disables header (and therefore module map) generation,
# regardless of the toolchain's default feature set.
NO_GENERATE_HEADER_CONFIG_SETTINGS = {
    "//command_line_option:features": [
        "swift.no_generated_header",
    ],
}

generate_header_and_module_map_provider_test = make_provider_test_rule(
    config_settings = GENERATE_HEADER_AND_MODULE_MAP_CONFIG_SETTINGS,
)

generate_header_and_module_map_failure_test = make_analysis_failure_test_rule(
    config_settings = GENERATE_HEADER_AND_MODULE_MAP_CONFIG_SETTINGS,
)

no_generate_header_provider_test = make_provider_test_rule(
    config_settings = NO_GENERATE_HEADER_CONFIG_SETTINGS,
)

def generated_header_test_suite(name = "generated_header"):
    """Test suite for `swift_library.generated_header`.

    Args:
        name: The name prefix for all the nested tests
    """

    # Verify that the generated header by default gets an automatically
    # generated name and is an output of the rule.
    generate_header_and_module_map_provider_test(
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

    # Verify that the generated header is propagated in `SwiftInfo`.
    generate_header_and_module_map_provider_test(
        name = "{}_automatically_named_header_is_propagated".format(name),
        expected_files = [
            "test/fixtures/generated_header/auto_header-Swift.h",
        ],
        field = "transitive_generated_headers",
        provider = "SwiftInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:auto_header",
    )

    # Verify that the generated module map is propagated in `apple_common.Objc`.
    # TODO(b/148604334): Enable this when it analyzes correctly on all platforms.
    # generate_header_and_module_map_provider_test(
    #     name = "{}_automatically_named_header_modulemap_is_propagated".format(name),
    #     expected_files = [
    #         "test/fixtures/generated_header/auto_header.modulemaps/module.modulemap",
    #     ],
    #     field = "direct_module_maps",
    #     provider = "apple_common.Objc",
    #     tags = [name],
    #     target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:auto_header",
    # )

    # Verify that the explicit generated header is an output of the rule and
    # that the automatically named one is *not*.
    generate_header_and_module_map_provider_test(
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
    generate_header_and_module_map_failure_test(
        name = "{}_invalid_extension".format(name),
        expected_message = "The generated header for a Swift module must have a '.h' extension",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:invalid_extension",
    )

    # Verify that the build analyzes if a path separator is used.
    generate_header_and_module_map_provider_test(
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

    # Verify that the header is not generated if the feature
    # `swift.no_generated_header` set, when using an automatically named header.
    no_generate_header_provider_test(
        name = "{}_no_header".format(name),
        expected_files = [
            "-test/fixtures/generated_header/auto_header-Swift.h",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:auto_header",
    )

    # Verify that the header is not generated if the feature
    # `swift.no_generated_header` set, even when specifying an explicit header
    # name.
    no_generate_header_provider_test(
        name = "{}_no_explicit_header".format(name),
        expected_files = [
            "-test/fixtures/generated_header/SomeOtherName.h",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/generated_header:explicit_header",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

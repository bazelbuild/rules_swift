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

"""Unit and analysis tests for package specs, package configurations, feature allowlists, and copt flags."""

load(
    "@bazel_skylib//lib:unittest.bzl",
    "analysistest",
    "asserts",
    "unittest",
)
load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftFeatureAllowlistInfo",
    "SwiftPackageConfigurationInfo",
)
load(
    "@build_bazel_rules_swift//swift:swift_common.bzl",
    "swift_common",
)
load(
    "@build_bazel_rules_swift//swift/internal:package_specs.bzl",
    "label_matches_package_specs",
    "parse_package_specs",
)
load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:analysis_failure_test.bzl",
    "analysis_failure_test",
)

visibility([
    "@build_bazel_rules_swift//test/...",
])

_FeatureConfigurationTestInfo = provider(
    doc = "Captures the configured Swift features for testing.",
    fields = ["feature_configuration"],
)

def _build_custom_toolchains(toolchains, feature_allowlists, package_configurations):
    custom_swift_toolchain = struct(
        cc_language = toolchains.swift.cc_language,
        feature_allowlists = [
            target[SwiftFeatureAllowlistInfo]
            for target in feature_allowlists
        ],
        package_configurations = [
            target[SwiftPackageConfigurationInfo]
            for target in package_configurations
        ],
        requested_features = toolchains.swift.requested_features,
        unsupported_features = toolchains.swift.unsupported_features,
    )
    return struct(
        cc = toolchains.cc,
        swift = custom_swift_toolchain,
    )

def _feature_configuration_test_fixture_impl(ctx):
    toolchains = _build_custom_toolchains(
        toolchains = swift_common.find_all_toolchains(ctx),
        feature_allowlists = ctx.attr.feature_allowlists,
        package_configurations = ctx.attr.package_configurations,
    )
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features,
        toolchains = toolchains,
        unsupported_features = ctx.disabled_features,
    )
    return [
        _FeatureConfigurationTestInfo(
            feature_configuration = feature_configuration,
        ),
    ]

feature_configuration_test_fixture = rule(
    attrs = {
        "feature_allowlists": attr.label_list(
            providers = [SwiftFeatureAllowlistInfo],
        ),
        "package_configurations": attr.label_list(
            providers = [SwiftPackageConfigurationInfo],
        ),
    },
    doc = "Configures Swift features with custom package configurations and allowlists.",
    fragments = ["cpp"],
    implementation = _feature_configuration_test_fixture_impl,
    toolchains = swift_common.use_all_toolchains(),
)

def _feature_configuration_test_aspect_impl(_target, aspect_ctx):
    toolchains = _build_custom_toolchains(
        toolchains = swift_common.find_all_toolchains(aspect_ctx),
        feature_allowlists = aspect_ctx.rule.attr.feature_allowlists,
        package_configurations = aspect_ctx.rule.attr.package_configurations,
    )
    feature_configuration = swift_common.configure_features(
        ctx = aspect_ctx,
        requested_features = aspect_ctx.features,
        toolchains = toolchains,
        unsupported_features = aspect_ctx.disabled_features,
    )
    return [
        _FeatureConfigurationTestInfo(
            feature_configuration = feature_configuration,
        ),
    ]

feature_configuration_test_aspect = aspect(
    doc = "Configures Swift features from an aspect context to test allowlist aspect_ids.",
    fragments = ["cpp"],
    implementation = _feature_configuration_test_aspect_impl,
    toolchains = swift_common.use_all_toolchains(),
)

def _passive_feature_fixture_impl(_ctx):
    return []

passive_feature_fixture = rule(
    attrs = {
        "feature_allowlists": attr.label_list(
            providers = [SwiftFeatureAllowlistInfo],
        ),
        "package_configurations": attr.label_list(
            providers = [SwiftPackageConfigurationInfo],
        ),
    },
    doc = "Holds allowlists and package configurations for aspect-based testing without running configure_features in the rule.",
    implementation = _passive_feature_fixture_impl,
)

def _apply_feature_configuration_test_aspect_impl(ctx):
    return [ctx.attr.target[_FeatureConfigurationTestInfo]]

apply_feature_configuration_test_aspect = rule(
    attrs = {
        "target": attr.label(
            aspects = [feature_configuration_test_aspect],
            mandatory = True,
        ),
    },
    doc = "Applies `feature_configuration_test_aspect` to `target` and forwards its provider.",
    implementation = _apply_feature_configuration_test_aspect_impl,
)

def _feature_configuration_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    feature_configuration = (
        target_under_test[_FeatureConfigurationTestInfo].feature_configuration
    )

    for feature_name in ctx.attr.expected_enabled_features:
        asserts.true(
            env,
            swift_common.is_enabled(
                feature_configuration = feature_configuration,
                feature_name = feature_name,
            ),
            "Expected feature '{}' to be enabled on '{}', but it was disabled.".format(
                feature_name,
                target_under_test.label,
            ),
        )

    for feature_name in ctx.attr.expected_disabled_features:
        asserts.false(
            env,
            swift_common.is_enabled(
                feature_configuration = feature_configuration,
                feature_name = feature_name,
            ),
            "Expected feature '{}' to be disabled on '{}', but it was enabled.".format(
                feature_name,
                target_under_test.label,
            ),
        )

    return analysistest.end(env)

feature_configuration_test = analysistest.make(
    _feature_configuration_test_impl,
    attrs = {
        "expected_disabled_features": attr.string_list(),
        "expected_enabled_features": attr.string_list(),
    },
)

def _package_specs_unit_test_impl(ctx):
    env = unittest.begin(ctx)
    ws = Label("//foo:bar").workspace_name

    test_cases = [
        # 1. Exact package specification.
        struct(
            specs = ["//foo/bar"],
            matching = ["//foo/bar:target"],
            non_matching = [
                "//foo:target",
                "//foo/bar/baz:target",
                "//foo/bar_qux:target",
            ],
        ),
        # 2. Recursive subpackage specification.
        struct(
            specs = ["//foo/..."],
            matching = [
                "//foo:t",
                "//foo/bar:t",
                "//foo/bar/baz:t",
            ],
            non_matching = [
                "//foobar:t",
                "//other:t",
            ],
        ),
        # 3. Root wildcard specification.
        struct(
            specs = ["//..."],
            matching = [
                "//:root_target",
                "//foo:t",
                "//foo/bar/baz:t",
            ],
            non_matching = [],
        ),
        # 4. Negative exclusions take precedence regardless of ordering.
        struct(
            specs = ["//foo/...", "-//foo/bar/..."],
            matching = [
                "//foo:t",
                "//foo/baz:t",
                "//foo/bar_qux:t",
            ],
            non_matching = [
                "//foo/bar:t",
                "//foo/bar/sub:t",
            ],
        ),
        struct(
            specs = ["-//foo/bar/...", "//foo/..."],
            matching = [
                "//foo:t",
                "//foo/baz:t",
                "//foo/bar_qux:t",
            ],
            non_matching = [
                "//foo/bar:t",
                "//foo/bar/sub:t",
            ],
        ),
        # 5. Exact package exclusion leaves subpackages matched.
        struct(
            specs = ["//foo/...", "-//foo/bar"],
            matching = ["//foo/bar/sub:t"],
            non_matching = ["//foo/bar:t"],
        ),
    ]

    for case in test_cases:
        parsed = parse_package_specs(
            package_specs = case.specs,
            workspace_name = ws,
        )
        for label_str in case.matching:
            asserts.true(
                env,
                label_matches_package_specs(
                    label = Label(label_str),
                    package_specs = parsed,
                ),
                "Expected '{}' to match specs {}".format(label_str, case.specs),
            )
        for label_str in case.non_matching:
            asserts.false(
                env,
                label_matches_package_specs(
                    label = Label(label_str),
                    package_specs = parsed,
                ),
                "Expected '{}' not to match specs {}".format(label_str, case.specs),
            )

    return unittest.end(env)

package_specs_unit_test = unittest.make(_package_specs_unit_test_impl)

per_module_swiftcopt_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "@build_bazel_rules_swift//swift:per_module_swiftcopt": [
            "@build_bazel_rules_swift//test/fixtures/package_configuration:target_a=-DFLAG_FOR_A,-DSECOND_FLAG_FOR_A",
        ],
    },
)

copt_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "@build_bazel_rules_swift//swift:copt": [
            "-DGLOBAL_SWIFT_COPT",
        ],
    },
)

def package_configuration_test_suite(name, tags = []):
    """Test suite for `package_specs`, `swift_package_configuration`, `swift_feature_allowlist`, and copt flags.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # 1. Unit tests for `package_specs.bzl`.
    package_specs_unit_test(
        name = "{}_package_specs_unit_test".format(name),
        tags = all_tags,
    )

    # 2. Invalid `packages` specification failure tests on
    # `swift_package_configuration` and `swift_feature_allowlist`.
    analysis_failure_test(
        name = "{}_package_config_relative_path_fails".format(name),
        expected_message = "A package list may only contain absolute labels (found 'foo/bar').",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:package_config_relative_path",
    )

    analysis_failure_test(
        name = "{}_package_config_target_reference_fails".format(name),
        expected_message = "A package list may only list packages, not targets (found 'foo/bar:target').",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:package_config_target_reference",
    )

    analysis_failure_test(
        name = "{}_package_config_legacy_pkg_suffix_fails".format(name),
        expected_message = "The package list should contain only the package name, without a ':__pkg__' suffix (found 'foo/bar:__pkg__').",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:package_config_legacy_pkg_suffix",
    )

    analysis_failure_test(
        name = "{}_package_config_legacy_subpackages_suffix_fails".format(name),
        expected_message = "To list a package and all of its subpackages, write the package name followed by '/...', not the ':__subpackages__' metatarget (found 'foo/bar:__subpackages__').",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:package_config_legacy_subpackages_suffix",
    )

    analysis_failure_test(
        name = "{}_allowlist_relative_path_fails".format(name),
        expected_message = "A package list may only contain absolute labels (found 'foo/bar').",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:allowlist_relative_path",
    )

    analysis_failure_test(
        name = "{}_allowlist_target_reference_fails".format(name),
        expected_message = "A package list may only list packages, not targets (found 'foo/bar:target').",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:allowlist_target_reference",
    )

    # 3. `swift_package_configuration` and `swift_feature_allowlist` evaluation
    # tests via `configure_features`.
    feature_configuration_test(
        name = "{}_package_config_matching_package".format(name),
        expected_disabled_features = [
            "swift.layering_check_swift",
            "swift.pkg_disabled_feature",
        ],
        expected_enabled_features = [
            "swift.pkg_enabled_feature",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_with_matching_pkg_config",
    )

    feature_configuration_test(
        name = "{}_package_config_overridden_by_target".format(name),
        expected_disabled_features = [
            "swift.pkg_enabled_feature",
        ],
        expected_enabled_features = [
            "swift.layering_check_swift",
            "swift.pkg_disabled_feature",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_overriding_pkg_config",
    )

    feature_configuration_test(
        name = "{}_package_config_excluded_package".format(name),
        expected_disabled_features = [
            "swift.excluded_pkg_feature",
        ],
        expected_enabled_features = [
            "swift.layering_check_swift",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_with_excluded_pkg_config",
    )

    feature_configuration_test(
        name = "{}_allowlist_permits_matching_package".format(name),
        expected_disabled_features = [
            "swift.cannot_disable_feature",
        ],
        expected_enabled_features = [
            "swift.restricted_feature",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_allowed_by_allowlist",
    )

    analysis_failure_test(
        name = "{}_allowlist_rejects_enable_in_non_matching_package".format(name),
        expected_message = "Feature 'swift.restricted_feature' is not allowed to be set by the target",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_disallowed_enable_by_allowlist",
    )

    analysis_failure_test(
        name = "{}_allowlist_rejects_disable_in_non_matching_package".format(name),
        expected_message = "Feature '-swift.cannot_disable_feature' is not allowed to be set by the target",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_disallowed_disable_by_allowlist",
    )

    feature_configuration_test(
        name = "{}_overlapping_allowlists_all_matching_succeeds".format(name),
        expected_enabled_features = [
            "swift.restricted_feature",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_overlapping_allowlists_allowed",
    )

    analysis_failure_test(
        name = "{}_overlapping_allowlists_one_non_matching_fails".format(name),
        expected_message = "Feature 'swift.restricted_feature' is not allowed to be set by the target",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_overlapping_allowlists_disallowed",
    )

    feature_configuration_test(
        name = "{}_allowlist_bypassed_by_aspect_id".format(name),
        expected_enabled_features = [
            "swift.restricted_feature",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:fixture_allowed_via_aspect_id",
    )

    # 4. `--@build_bazel_rules_swift//swift:per_module_swiftcopt` and
    # `--@build_bazel_rules_swift//swift:copt` build setting tests.
    per_module_swiftcopt_action_command_line_test(
        name = "{}_per_module_swiftcopt_applies_to_matching_target".format(name),
        expected_argv = [
            "-DFLAG_FOR_A",
            "-DSECOND_FLAG_FOR_A",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:target_a",
    )

    per_module_swiftcopt_action_command_line_test(
        name = "{}_per_module_swiftcopt_does_not_apply_to_other_target".format(name),
        not_expected_argv = [
            "-DFLAG_FOR_A",
            "-DSECOND_FLAG_FOR_A",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:target_b",
    )

    copt_action_command_line_test(
        name = "{}_copt_applies_to_target_a".format(name),
        expected_argv = [
            "-DGLOBAL_SWIFT_COPT",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:target_a",
    )

    copt_action_command_line_test(
        name = "{}_copt_applies_to_target_b".format(name),
        expected_argv = [
            "-DGLOBAL_SWIFT_COPT",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/package_configuration:target_b",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

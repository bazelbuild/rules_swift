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

"""Tests for `swift.label_as_module_name` and module name derivation."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "@build_bazel_rules_swift//swift:module_name.bzl",
    "derive_swift_module_name",
    "physical_swift_module_name",
)
load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

def _derive_swift_module_name_unit_test_impl(ctx):
    env = unittest.begin(ctx)

    label_feature_config = struct(
        _enabled_features = ["swift.label_as_module_name"],
    )
    for args, feature_config, expected in [
        (("foo/bar", "baz"), None, "foo_bar_baz"),
        ((Label("//foo/bar:baz"),), None, "foo_bar_baz"),
        (("123", "456"), None, "_123_456"),
        (("foo/bar", "baz"), label_feature_config, "`//foo/bar:baz`"),
        (("foo/bar", "bar"), label_feature_config, "`//foo/bar`"),
        ((Label("//foo/bar:baz"),), label_feature_config, "`//foo/bar:baz`"),
        ((Label("//foo/bar:bar"),), label_feature_config, "`//foo/bar`"),
    ]:
        asserts.equals(
            env,
            expected,
            derive_swift_module_name(
                feature_configuration = feature_config,
                *args
            ),
        )

    return unittest.end(env)

derive_swift_module_name_unit_test = unittest.make(
    _derive_swift_module_name_unit_test_impl,
)

def _physical_swift_module_name_unit_test_impl(ctx):
    env = unittest.begin(ctx)

    for input_name, expected in [
        ("ValidIdentifier_123", "ValidIdentifier_123"),
        ("`//foo/bar:baz`", "foo_bar_baz"),
        # TODO(b/383316205): Fix physical names for module names that look like shorthand labels.
        ("`//foo/bar`", "foo_bar"),
        ("`//123/bar:baz`", "_123_bar_baz"),
        ("//foo/bar:baz", "foo_bar_baz"),
    ]:
        asserts.equals(env, expected, physical_swift_module_name(input_name))

    return unittest.end(env)

physical_swift_module_name_unit_test = unittest.make(
    _physical_swift_module_name_unit_test_impl,
)

def label_module_name_test_suite(name, tags = []):
    """Test suite for `swift.label_as_module_name`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    derive_swift_module_name_unit_test(
        name = "{}_derive_swift_module_name_unit_test".format(name),
        tags = all_tags,
    )

    physical_swift_module_name_unit_test(
        name = "{}_physical_swift_module_name_unit_test".format(name),
        tags = all_tags,
    )

    # Verify that a target whose name differs from its package basename records
    # the full backtick-escaped label in `source_name` and the escaped
    # identifier in `name`.
    provider_test(
        name = "{}_child_source_name".format(name),
        expected_values = [
            "`@build_bazel_rules_swift//test/fixtures/label_module_name:child`",
        ],
        field = "direct_modules.source_name",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/label_module_name:child",
    )

    provider_test(
        name = "{}_child_physical_name".format(name),
        expected_values = [
            "third_party_bazel_rules_rules_swift_test_fixtures_label_module_name_child",
        ],
        field = "direct_modules.name",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/label_module_name:child",
    )

    # Verify that a target whose name matches its package basename uses the
    # short-form label in `source_name`.
    provider_test(
        name = "{}_short_label_source_name".format(name),
        expected_values = [
            "`@build_bazel_rules_swift//test/fixtures/label_module_name`",
        ],
        field = "direct_modules.source_name",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/label_module_name",
    )

    # Verify that the compile command line passes `-module-name` with the
    # physical name and `-module-alias` flags mapping both the target's own
    # label and its dependencies' labels to their physical module names.
    action_command_line_test(
        name = "{}_compile_flags".format(name),
        expected_argv = [
            "-module-name third_party_bazel_rules_rules_swift_test_fixtures_label_module_name",
            "-module-alias @build_bazel_rules_swift//test/fixtures/label_module_name=third_party_bazel_rules_rules_swift_test_fixtures_label_module_name",
            "-module-alias @build_bazel_rules_swift//test/fixtures/label_module_name:child=third_party_bazel_rules_rules_swift_test_fixtures_label_module_name_child",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/label_module_name",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

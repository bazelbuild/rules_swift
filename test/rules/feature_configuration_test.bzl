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

"""Rules for testing Swift feature configurations."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//swift:swift_common.bzl", "swift_common")

_FeatureConfigurationTestInfo = provider(
    doc = "Captures the configured Swift features for testing.",
    fields = ["feature_configuration"],
)

def _feature_configuration_test_fixture_impl(ctx):
    toolchains = swift_common.find_all_toolchains(ctx)
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features + ctx.attr.additional_features,
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
        "additional_features": attr.string_list(),
    },
    doc = "Configures Swift features requested directly or injected by a rule.",
    fragments = ["cpp"],
    implementation = _feature_configuration_test_fixture_impl,
    toolchains = swift_common.use_all_toolchains(),
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

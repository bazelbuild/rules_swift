# Copyright 2018 The Bazel Authors. All rights reserved.
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

"""Helper functions for working with Bazel features."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:new_sets.bzl", "sets")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_COVERAGE",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_FULL_DEBUG_INFO",
)

def are_all_features_enabled(feature_configuration, feature_names):
    """Returns `True` if all features are enabled in the feature configuration.

    Args:
        feature_configuration: The Swift feature configuration, as returned by
            `swift_common.configure_features`.
        feature_names: The list of feature names to check.

    Returns:
        `True` if all of the given features are enabled in the feature
        configuration.
    """
    for feature_name in feature_names:
        if not is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = feature_name,
        ):
            return False
    return True

def configure_features(
        ctx,
        swift_toolchain,
        *,
        requested_features = [],
        unsupported_features = []):
    """Creates a feature configuration to be passed to Swift build APIs.

    This function calls through to `cc_common.configure_features` to configure
    underlying C++ features as well, and nests the C++ feature configuration
    inside the Swift one. Users who need to call C++ APIs that require a feature
    configuration can extract it by calling
    `swift_common.cc_feature_configuration(feature_configuration)`.

    Args:
        ctx: The rule context.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain
            being used to build. The C++ toolchain associated with the Swift
            toolchain is used to create the underlying C++ feature
            configuration.
        requested_features: The list of features to be enabled. This is
            typically obtained using the `ctx.features` field in a rule
            implementation function.
        unsupported_features: The list of features that are unsupported by the
            current rule. This is typically obtained using the
            `ctx.disabled_features` field in a rule implementation function.

    Returns:
        An opaque value representing the feature configuration that can be
        passed to other `swift_common` functions.
    """

    # The features to enable for a particular rule/target are the ones requested
    # by the toolchain, plus the ones requested by the target itself, *minus*
    # any that are explicitly disabled on the target itself.
    requested_features_set = sets.make(swift_toolchain.requested_features)
    requested_features_set = sets.union(
        requested_features_set,
        sets.make(requested_features),
    )
    requested_features_set = sets.difference(
        requested_features_set,
        sets.make(unsupported_features),
    )
    all_requested_features = sets.to_list(requested_features_set)

    all_unsupported_features = collections.uniq(
        swift_toolchain.unsupported_features + unsupported_features,
    )

    # Verify the consistency of Swift features requested vs. those that are not
    # supported by the toolchain. We don't need to do this for C++ features
    # because `cc_common.configure_features` handles verifying those.
    for feature in requested_features:
        if feature.startswith("swift.") and feature in all_unsupported_features:
            fail("Feature '{}' was requested, ".format(feature) +
                 "but it is not supported by the current toolchain or rule.")

    cc_feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        requested_features = all_requested_features,
        unsupported_features = all_unsupported_features,
    )
    return struct(
        cc_feature_configuration = cc_feature_configuration,
        requested_features = all_requested_features,
        unsupported_features = all_unsupported_features,
    )

def features_for_build_modes(ctx, objc_fragment = None):
    """Returns a list of Swift toolchain features for current build modes.

    This function explicitly breaks the "don't pass `ctx` as an argument"
    rule-of-thumb because it is internal and only called from the toolchain
    rules, so there is no concern about supporting differing call sites.

    Args:
        ctx: The current rule context.
        objc_fragment: The Objective-C configuration fragment, if available.

    Returns:
        A list of Swift toolchain features to enable.
    """
    compilation_mode = ctx.var["COMPILATION_MODE"]
    features = []
    features.append("swift.{}".format(compilation_mode))
    if ctx.configuration.coverage_enabled:
        features.append(SWIFT_FEATURE_COVERAGE)
    if compilation_mode in ("dbg", "fastbuild"):
        features.append(SWIFT_FEATURE_ENABLE_TESTING)
    if objc_fragment and objc_fragment.generate_dsym:
        features.append(SWIFT_FEATURE_FULL_DEBUG_INFO)
    return features

def get_cc_feature_configuration(feature_configuration):
    """Returns the C++ feature configuration in a Swift feature configuration.

    Args:
        feature_configuration: The Swift feature configuration, as returned from
            `swift_common.configure_features`.

    Returns:
        A C++ `FeatureConfiguration` value (see
        [`cc_common.configure_features`](https://docs.bazel.build/versions/master/skylark/lib/cc_common.html#configure_features)
        for more information).
    """
    return feature_configuration.cc_feature_configuration

def is_feature_enabled(feature_configuration, feature_name):
    """Returns `True` if the feature is enabled in the feature configuration.

    This function handles both Swift-specific features and C++ features so that
    users do not have to manually extract the C++ configuration in order to
    check it.

    Args:
        feature_configuration: The Swift feature configuration, as returned by
            `swift_common.configure_features`.
        feature_name: The name of the feature to check.

    Returns:
        `True` if the given feature is enabled in the feature configuration.
    """
    if feature_name.startswith("swift."):
        return feature_name in feature_configuration.requested_features
    else:
        return cc_common.is_enabled(
            feature_configuration = get_cc_feature_configuration(
                feature_configuration = feature_configuration,
            ),
            feature_name = feature_name,
        )

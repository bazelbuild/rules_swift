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
            being used to build. This is used to determine features that are
            enabled by default or unsupported by the toolchain, and the C++
            toolchain associated with the Swift toolchain is used to create the
            underlying C++ feature configuration.
        requested_features: The list of features to be enabled. This is
            typically obtained using the `ctx.features` field in a rule
            implementation function.
        unsupported_features: The list of features that are unsupported by the
            current rule. This is typically obtained using the
            `ctx.disabled_features` field in a rule implementation function.

    Returns:
        An opaque value representing the feature configuration that can be
        passed to other `swift_common` functions. Note that the structure of
        this value should otherwise not be relied on or inspected directly.
    """

    # The features to enable for a particular rule/target are the ones requested
    # by the toolchain, plus the ones requested by the target itself, *minus*
    # any that are explicitly disabled on the target or the toolchain.
    requestable_features_set = sets.make(swift_toolchain.requested_features)
    requestable_features_set = sets.union(
        requestable_features_set,
        sets.make(requested_features),
    )
    requestable_features_set = sets.difference(
        requestable_features_set,
        sets.make(unsupported_features),
    )
    requestable_features_set = sets.difference(
        requestable_features_set,
        sets.make(swift_toolchain.unsupported_features),
    )
    requestable_features = sets.to_list(requestable_features_set)

    cc_feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        requested_features = requestable_features,
        unsupported_features = unsupported_features,
    )
    return struct(
        _cc_feature_configuration = cc_feature_configuration,
        _enabled_features = requestable_features,
    )

def features_for_build_modes(ctx, objc_fragment = None, cpp_fragment = None):
    """Returns a list of Swift toolchain features for current build modes.

    This function explicitly breaks the "don't pass `ctx` as an argument"
    rule-of-thumb because it is internal and only called from the toolchain
    rules, so there is no concern about supporting differing call sites.

    Args:
        ctx: The current rule context.
        objc_fragment: The Objective-C configuration fragment, if available.
        cpp_fragment: The Cpp configuration fragment, if available.

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

    # TODO: Remove getattr once bazel is released with this change
    if cpp_fragment and getattr(cpp_fragment, "apple_generate_dsym", False):
        features.append(SWIFT_FEATURE_FULL_DEBUG_INFO)

    # TODO: Remove the objc_fragment usage once bazel is released with the C++ change
    if objc_fragment and getattr(objc_fragment, "generate_dsym", False):
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
    return feature_configuration._cc_feature_configuration

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
        return feature_name in feature_configuration._enabled_features
    else:
        return cc_common.is_enabled(
            feature_configuration = get_cc_feature_configuration(
                feature_configuration = feature_configuration,
            ),
            feature_name = feature_name,
        )

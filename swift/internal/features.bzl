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

    # Always disable these two features so that any `cc_common` APIs called by
    # `swift_common` APIs don't cause certain actions to be created (for
    # example, when using `cc_common.compile` to create the compilation context
    # for a generated header).
    unsupported_features = list(unsupported_features)
    unsupported_features.extend([
        # Avoid making the `grep_includes` tool a requirement of Swift
        # compilation APIs/rules that generate a header.
        "cc_include_scanning",
        # Don't register parse-header actions for generated headers.
        "parse_headers",
    ])

    if swift_toolchain.feature_allowlists:
        _check_allowlists(
            allowlists = swift_toolchain.feature_allowlists,
            label = ctx.label,
            requested_features = requested_features,
            unsupported_features = unsupported_features,
        )

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

def features_for_build_modes(ctx, cpp_fragment = None):
    """Returns a list of Swift toolchain features for current build modes.

    This function explicitly breaks the "don't pass `ctx` as an argument"
    rule-of-thumb because it is internal and only called from the toolchain
    rules, so there is no concern about supporting differing call sites.

    Args:
        ctx: The current rule context.
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
    if cpp_fragment and cpp_fragment.apple_generate_dsym:
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

def _check_allowlists(
        *,
        allowlists,
        label,
        requested_features,
        unsupported_features):
    """Checks the toolchain's allowlists to verify the requested features.

    If any of the features requested to be enabled or disabled is not allowed in
    the target's package by one of the allowlists, the build will fail with an
    error message indicating the feature and the allowlist that denied it.

    Args:
        allowlists: A list of `SwiftFeatureAllowlistInfo` providers that will be
            checked.
        label: The label of the target being checked against the allowlist.
        requested_features: The list of features to be enabled. This is
            typically obtained using the `ctx.features` field in a rule
            implementation function.
        unsupported_features: The list of features that are unsupported by the
            current rule. This is typically obtained using the
            `ctx.disabled_features` field in a rule implementation function.
    """
    features_to_check = list(requested_features)
    features_to_check.extend(
        ["-{}".format(feature) for feature in unsupported_features],
    )

    for allowlist in allowlists:
        for feature_string in features_to_check:
            if not _is_feature_allowed_in_package(
                allowlist = allowlist,
                feature = feature_string,
                package = label.package,
                workspace_name = label.workspace_name,
            ):
                fail((
                    "Feature '{feature}' is not allowed to be set by the " +
                    "target '{target}'; see the allowlist at '{allowlist}' " +
                    "for more information."
                ).format(
                    allowlist = allowlist.allowlist_label,
                    feature = feature_string,
                    target = str(label),
                ))

def _is_feature_allowed_in_package(
        allowlist,
        feature,
        package,
        workspace_name = None):
    """Returns a value indicating whether a feature is allowed in a package.

    Args:
        allowlist: The `SwiftFeatureAllowlistInfo` provider that contains the
            allowlist.
        feature: The name of the feature (or its negation) being checked.
        package: The package part of the label being checked for access (e.g.,
            the value of `ctx.label.package`).
        workspace_name: The workspace name part of the label being checked for
            access (e.g., the value of `ctx.label.workspace_name`).

    Returns:
        True if the feature is allowed to be used in the package, or False if it
        is not.
    """

    # Any feature not managed by the allowlist is allowed by default.
    if feature not in allowlist.managed_features:
        return True

    if workspace_name:
        package_spec = "@{}//{}".format(workspace_name, package)
    else:
        package_spec = "//{}".format(package)

    is_allowed = False
    for package_info in allowlist.packages:
        if package_info.match_subpackages:
            is_match = (
                package_spec == package_info.package or
                package_spec.startswith(package_info.package + "/")
            )
        else:
            is_match = package_spec == package_info.package

        if is_match:
            # Package exclusions always take precedence over package inclusions,
            # so if we have an exclusion match, return false immediately.
            if package_info.excluded:
                return False
            else:
                is_allowed = True

    return is_allowed

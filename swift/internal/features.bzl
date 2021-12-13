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
load(":package_specs.bzl", "label_matches_package_specs")

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

    all_requestable_features, all_unsupported_features = _compute_features(
        label = ctx.label,
        requested_features = requested_features,
        swift_toolchain = swift_toolchain,
        unsupported_features = unsupported_features,
    )
    cc_feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        requested_features = all_requestable_features,
        unsupported_features = all_unsupported_features,
    )
    return struct(
        _cc_feature_configuration = cc_feature_configuration,
        _enabled_features = all_requestable_features,
        # This is naughty, but APIs like `cc_common.compile` do far worse and
        # "cheat" by accessing the full rule context through a back-reference in
        # the `Actions` object so they can get access to the `-bin` and
        # `-genfiles` roots, among other values. Since the feature configuration
        # is a required argument of all action-registering APIs, and the context
        # is a required argument when creating it, we'll take that opportunity
        # to stash any context-dependent values that we want to access in the
        # other APIs, so they don't have to be passed manually by the callers.
        _bin_dir = ctx.bin_dir,
        _genfiles_dir = ctx.genfiles_dir,
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
            # Any feature not managed by the allowlist is allowed by default.
            if feature_string not in allowlist.managed_features:
                continue

            if not label_matches_package_specs(
                label = label,
                package_specs = allowlist.package_specs,
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

def _compute_features(
        *,
        label,
        requested_features,
        swift_toolchain,
        unsupported_features):
    """Computes the features to enable/disable for a target.

    Args:
        label: The label of the target whose features are being configured.
        requested_features: The list of features requested by the rule/aspect
            configuration (i.e., the features specified in positive form by the
            `features` attribute of the target, the `package()` rule in the
            package, and the `--features` command line option).
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain
            being used to build.
        unsupported_features: The list of features unsupported by the
            rule/aspect configuration (i.e., the features specified in negative
            form by the `features` attribute of the target, the `package()` rule
            in the package, and the `--features` command line option).

    Returns:
        A tuple containing two elements:

        1.  The list of features that should be enabled for the target.
        2.  The list of features that should be disabled for the target.
    """

    # The features to enable for a particular rule/target are the ones requested
    # by the toolchain, plus the ones requested by any matching package
    # configurations, plus the ones requested by the target itself; *minus*
    # any that are explicitly disabled on the toolchain, the matching package
    # configurations, or the target itself.
    requested_features_set = sets.make(swift_toolchain.requested_features)
    unsupported_features_set = sets.make(swift_toolchain.unsupported_features)

    for package_configuration in swift_toolchain.package_configurations:
        if label_matches_package_specs(
            label = label,
            package_specs = package_configuration.package_specs,
        ):
            if package_configuration.enabled_features:
                requested_features_set = sets.union(
                    requested_features_set,
                    sets.make(package_configuration.enabled_features),
                )
            if package_configuration.disabled_features:
                unsupported_features_set = sets.union(
                    unsupported_features_set,
                    sets.make(package_configuration.disabled_features),
                )

    if requested_features:
        requested_features_set = sets.union(
            requested_features_set,
            sets.make(requested_features),
        )
    if unsupported_features:
        unsupported_features_set = sets.union(
            unsupported_features_set,
            sets.make(unsupported_features),
        )

    # If the same feature is present in both sets, being unsupported takes
    # priority, so remove any of those from the requested set.
    requestable_features_set = sets.difference(
        requested_features_set,
        unsupported_features_set,
    )
    return (
        sets.to_list(requestable_features_set),
        sets.to_list(unsupported_features_set),
    )

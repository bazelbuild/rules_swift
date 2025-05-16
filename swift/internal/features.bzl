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
    "SWIFT_FEATURE_CHECKED_EXCLUSIVITY",
    "SWIFT_FEATURE_COVERAGE",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_DISABLE_CLANG_SPI",
    "SWIFT_FEATURE_ENABLE_BARE_SLASH_REGEX",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_FULL_DEBUG_INFO",
    "SWIFT_FEATURE_INTERNALIZE_AT_LINK",
    "SWIFT_FEATURE_LAYERING_CHECK_SWIFT",
    "SWIFT_FEATURE_OPT_USES_CMO",
)
load(":package_specs.bzl", "label_matches_package_specs")

visibility([
    "@build_bazel_rules_swift//swift/...",
])

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
        toolchains,
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
        toolchains: The toolchains that are used to determine which features are
            enabled by default or unsupported. This is typically obtained using
            `swift_common.find_all_toolchains()`.
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

    # Always disable this feature so that any `cc_common` APIs called by
    # `swift_common` APIs don't cause certain actions to be created (for
    # example, when using `cc_common.compile` to create the compilation context
    # for a generated header).
    unsupported_features = list(unsupported_features)
    unsupported_features.append("cc_include_scanning")

    # HACK: This is the only way today to check whether the caller is inside an
    # aspect. We have to do this because accessing `ctx.aspect_ids` halts the
    # build if called from outside an aspect, but we can't use `hasattr` to
    # check if it's safe because the attribute is always present on both rule
    # and aspect contexts.
    # TODO: b/319132714 - Replace this with a real API.
    is_aspect = repr(ctx).startswith("<aspect context ")
    if is_aspect and ctx.aspect_ids:
        # It doesn't appear to be documented anywhere, but according to the
        # Bazel team, the last element in this list is the currently running
        # aspect.
        aspect_id = ctx.aspect_ids[len(ctx.aspect_ids) - 1]
    else:
        aspect_id = None

    if toolchains.swift.feature_allowlists:
        _check_allowlists(
            allowlists = toolchains.swift.feature_allowlists,
            aspect_id = aspect_id,
            label = ctx.label,
            requested_features = requested_features,
            unsupported_features = unsupported_features,
        )

    # Disable CMO for builds in `exec` configurations so that we can use
    # parallelized compilation for build tools written in Swift. The speedup
    # from parallelized compilation is significantly higher than the performance
    # loss from disabling CMO.
    #
    # HACK: There is no supported API yet to detect whether a build is in an
    # `exec` configuration. https://github.com/bazelbuild/bazel/issues/14444.
    if "-exec" in ctx.bin_dir.path or "/host/" in ctx.bin_dir.path:
        unsupported_features.append(SWIFT_FEATURE_OPT_USES_CMO)
    else:
        requested_features = list(requested_features)
        requested_features.append(SWIFT_FEATURE_OPT_USES_CMO)

    all_requestable_features, all_unsupported_features = _compute_features(
        label = ctx.label,
        requested_features = requested_features,
        swift_toolchain = toolchains.swift,
        unsupported_features = unsupported_features,
    )
    cc_feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = toolchains.cc,
        language = toolchains.swift.cc_language,
        requested_features = all_requestable_features,
        unsupported_features = all_unsupported_features,
    )

    # Swift generated Objective-C headers are not compatible with
    # `parse_headers` actions. But, we don't want to disable `parse_headers` for
    # all actions performed by the toolchain, only the one that compiles the
    # generated header into an explicit module. So, we (lazily) create a second
    # feature configuration that will be used by that specific action.
    def cc_feature_configuration_no_parse_headers():
        return cc_common.configure_features(
            ctx = ctx,
            cc_toolchain = toolchains.cc,
            language = toolchains.swift.cc_language,
            requested_features = all_requestable_features,
            unsupported_features = all_unsupported_features + ["parse_headers"],
        )

    return struct(
        _cc_feature_configuration = cc_feature_configuration,
        _cc_feature_configuration_no_parse_headers = cc_feature_configuration_no_parse_headers,
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
        # Capture the label of the calling target so that it can be passed to
        # the worker as additional context, without requiring the user to pass
        # it in separately.
        _label = ctx.label,
    )

def features_for_build_modes(ctx, cpp_fragment = None):
    """Returns features to request and disable for current build modes.

    This function explicitly breaks the "don't pass `ctx` as an argument"
    rule-of-thumb because it is internal and only called from the toolchain
    rules, so there is no concern about supporting differing call sites.

    Args:
        ctx: The current rule context.
        cpp_fragment: The `cpp` configuration fragment, if available.

    Returns:
        A tuple containing two lists:

        1.  A list of Swift toolchain features to requested (enable).
        2.  A list of Swift toolchain features that are unsupported (disabled).
    """
    requested_features = []
    unsupported_features = []

    compilation_mode = ctx.var["COMPILATION_MODE"]
    requested_features.append("swift.{}".format(compilation_mode))
    if compilation_mode in ("dbg", "fastbuild"):
        requested_features.append(SWIFT_FEATURE_ENABLE_TESTING)

    if ctx.configuration.coverage_enabled:
        requested_features.append(SWIFT_FEATURE_COVERAGE)

    if cpp_fragment and cpp_fragment.apple_generate_dsym:
        requested_features.append(SWIFT_FEATURE_FULL_DEBUG_INFO)

    return requested_features, unsupported_features

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

def default_features_for_toolchain(ctx, target_triple):
    """Enables a common set of swift features based on build configuration.

    We have a common set of features we'd like to enable for both
    swift_toolchain and xcode_swift_toolchain. This method configures that set
    of features based on what exec platform we're using (linux or apple) and
    what platform we're targetting (linux, macos, ios, etc.).

    Args:
        ctx: Context of the swift toolchain rule building this list of features.
        target_triple: Target triple configured for our toolchain.

    Returns:
        List of default features for our toolchain's build config.
    """

    # Common features we turn on regardless of target.
    features = [
        SWIFT_FEATURE_CHECKED_EXCLUSIVITY,
        SWIFT_FEATURE_DISABLE_CLANG_SPI,
        SWIFT_FEATURE_ENABLE_BARE_SLASH_REGEX,
        SWIFT_FEATURE_ENABLE_BATCH_MODE,
        SWIFT_FEATURE_INTERNALIZE_AT_LINK,
        SWIFT_FEATURE_LAYERING_CHECK_SWIFT,
    ]

    # Apple specific features
    if target_triple.vendor == "apple":
        features.append(SWIFT_FEATURE_DEBUG_PREFIX_MAP)

    return features

def upcoming_and_experimental_features(feature_configuration):
    """Extracts the upcoming and experimental feature names from the config.

    Args:
        feature_configuration: The Swift feature configuration.

    Returns:
        A tuple containing the following elements:

        1.  The `list` of requested upcoming features (with the
            `swift.upcoming.` prefix removed).
        2.  The `list` of requested experimental features (with the
            `swift.experimental.` prefix removed).
    """
    upcoming_prefix = "swift.upcoming."
    experimental_prefix = "swift.experimental."
    upcoming = []
    experimental = []

    for feature in feature_configuration._enabled_features:
        if feature.startswith(upcoming_prefix):
            upcoming.append(feature[len(upcoming_prefix):])
        elif feature.startswith(experimental_prefix):
            experimental.append(feature[len(experimental_prefix):])

    return (upcoming, experimental)

def warnings_as_errors_from_features(feature_configuration):
    """Extracts the diagnostic IDs to treat as errors in post-processing.

    Args:
        feature_configuration: The Swift feature configuration.

    Returns:
        The `list` of diagnostic IDs to treat as errors.
    """
    prefix = "swift.werror."
    warnings_as_errors = []

    for feature in feature_configuration._enabled_features:
        if feature.startswith(prefix):
            warnings_as_errors.append(feature[len(prefix):])

    return warnings_as_errors

def _check_allowlists(
        *,
        allowlists,
        aspect_id,
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
        aspect_id: The identifier of the currently running aspect that has been
            applied to the target that is creating the feature configuration, or
            `None` if it is not being called from an aspect.
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

            # If the current aspect is permitted by the allowlist, we can allow
            # the usage without looking at the package specs.
            if aspect_id in allowlist.aspect_ids:
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
        unsupported_features: The list of features disabled by the rule/aspect
            configuration (i.e., the features specified in negative form by
            the `features` attribute of the target, the `package()` rule
            in the package, and the `--features` command line option).

    Returns:
        A tuple containing two elements:

        1.  The list of features that should be enabled for the target.
        2.  The list of features that should be disabled for the target.
    """

    # This treats the requested and disabled features as coming from different layers. The layers
    # are applied from most general to most specific, with features requested or disabled by more
    # specific layers overriding those from more general layers. Features that are unsupported by
    # the toolchain are treated as the most specific layer of all.

    def _make_feature_updater():
        # Starlark doesn't support re-binding variables captured from an enclosing lexical scope
        # so we resort to mutation to achieve the same result.
        state = {
            "requested_features": sets.make([]),
            "disabled_features": sets.make([]),
        }

        def _update_features(newly_requested_features, newly_disabled_features):
            newly_requested_features_set = sets.make(newly_requested_features)
            newly_disabled_features_set = sets.make(newly_disabled_features)

            # If a feature is both requested and disabled at the same level, it is disabled.
            newly_requested_features_set = sets.difference(
                newly_requested_features_set,
                newly_disabled_features_set,
            )

            requested_features_set = state["requested_features"]
            disabled_features_set = state["disabled_features"]

            # If a feature was requested at a higher level then disabled more narrowly we must
            # remove it from the requested feature set.
            requested_features_set = sets.difference(
                requested_features_set,
                newly_disabled_features_set,
            )

            # If a feature was disabled at a higher level then requested more narrowly we must
            # remove it from the disabled feature set.
            disabled_features_set = sets.difference(
                disabled_features_set,
                newly_requested_features_set,
            )

            requested_features_set = sets.union(
                requested_features_set,
                newly_requested_features_set,
            )
            disabled_features_set = sets.union(
                disabled_features_set,
                newly_disabled_features_set,
            )

            state["requested_features"] = requested_features_set
            state["disabled_features"] = disabled_features_set

        def _requested_features():
            return sets.to_list(state["requested_features"])

        def _disabled_features():
            return sets.to_list(state["disabled_features"])

        return struct(
            update_features = _update_features,
            requested_features = _requested_features,
            disabled_features = _disabled_features,
        )

    feature_updater = _make_feature_updater()

    # Features requested by the toolchain provide the default set of features.
    # Unsupported features are not a default, but an override, and are applied later.
    feature_updater.update_features(swift_toolchain.requested_features, [])

    for package_configuration in swift_toolchain.package_configurations:
        if label_matches_package_specs(
            label = label,
            package_specs = package_configuration.package_specs,
        ):
            feature_updater.update_features(
                package_configuration.enabled_features,
                package_configuration.disabled_features,
            )

    # Features specified at the target, package, or `--features` level override any from the
    # toolchain or toolchain-level package configuration.
    feature_updater.update_features(requested_features, unsupported_features)

    # Features that are unsupported by the toolchain override any requests for those features.
    feature_updater.update_features([], swift_toolchain.unsupported_features)

    all_disabled_features = feature_updater.disabled_features()
    all_requested_features = feature_updater.requested_features()
    return (all_requested_features, all_disabled_features)

load(
    "//swift:swift_feature_allowlist.bzl",
    "swift_feature_allowlist",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_package_configuration.bzl",
    "swift_package_configuration",
)
load(
    "//test:package_configuration_tests.bzl",
    "apply_feature_configuration_test_aspect",
    "feature_configuration_test_fixture",
    "passive_feature_fixture",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

# -----------------------------------------------------------------------------
# Invalid `packages` specifications for failure testing.

swift_package_configuration(
    name = "package_config_relative_path",
    configured_features = ["swift.some_feature"],
    packages = ["foo/bar"],
    tags = FIXTURE_TAGS,
)

swift_package_configuration(
    name = "package_config_target_reference",
    configured_features = ["swift.some_feature"],
    packages = ["//foo/bar:target"],
    tags = FIXTURE_TAGS,
)

swift_package_configuration(
    name = "package_config_legacy_pkg_suffix",
    configured_features = ["swift.some_feature"],
    packages = ["//foo/bar:__pkg__"],
    tags = FIXTURE_TAGS,
)

swift_package_configuration(
    name = "package_config_legacy_subpackages_suffix",
    configured_features = ["swift.some_feature"],
    packages = ["//foo/bar:__subpackages__"],
    tags = FIXTURE_TAGS,
)

swift_feature_allowlist(
    name = "allowlist_relative_path",
    managed_features = ["swift.restricted_feature"],
    packages = ["foo/bar"],
    tags = FIXTURE_TAGS,
)

swift_feature_allowlist(
    name = "allowlist_target_reference",
    managed_features = ["swift.restricted_feature"],
    packages = ["//foo/bar:target"],
    tags = FIXTURE_TAGS,
)

# -----------------------------------------------------------------------------
# Valid `swift_package_configuration` and `swift_feature_allowlist` fixtures.

swift_package_configuration(
    name = "matching_pkg_config",
    configured_features = [
        "swift.pkg_enabled_feature",
        "-swift.pkg_disabled_feature",
        "-swift.layering_check_swift",
    ],
    packages = [
        "//test/fixtures/...",
    ],
    tags = FIXTURE_TAGS,
)

swift_package_configuration(
    name = "excluded_pkg_config",
    configured_features = [
        "swift.excluded_pkg_feature",
        "-swift.layering_check_swift",
    ],
    packages = [
        "-" + "//test/fixtures/package_configuration",
        "//test/...",
    ],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_with_matching_pkg_config",
    package_configurations = [":matching_pkg_config"],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_overriding_pkg_config",
    features = [
        "-swift.pkg_enabled_feature",
        "swift.pkg_disabled_feature",
        "swift.layering_check_swift",
    ],
    package_configurations = [":matching_pkg_config"],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_with_excluded_pkg_config",
    package_configurations = [":excluded_pkg_config"],
    tags = FIXTURE_TAGS,
)

swift_feature_allowlist(
    name = "allowlist_matching_pkg",
    managed_features = [
        "swift.restricted_feature",
        "-swift.cannot_disable_feature",
    ],
    packages = [
        "//test/fixtures/package_configuration",
    ],
    tags = FIXTURE_TAGS,
)

swift_feature_allowlist(
    name = "allowlist_matching_subpackages",
    managed_features = [
        "swift.restricted_feature",
    ],
    packages = [
        "//test/fixtures/...",
    ],
    tags = FIXTURE_TAGS,
)

swift_feature_allowlist(
    name = "allowlist_other_pkg",
    managed_features = [
        "swift.restricted_feature",
        "-swift.cannot_disable_feature",
    ],
    packages = [
        "-" + "//test/fixtures/package_configuration",
        "//test/...",
    ],
    tags = FIXTURE_TAGS,
)

swift_feature_allowlist(
    name = "allowlist_with_aspect_id",
    aspect_ids = [
        "//test:package_configuration_tests.bzl%feature_configuration_test_aspect",
    ],
    managed_features = [
        "swift.restricted_feature",
    ],
    packages = [
        "-" + "//test/fixtures/package_configuration",
        "//test/...",
    ],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_allowed_by_allowlist",
    feature_allowlists = [":allowlist_matching_pkg"],
    features = [
        "swift.restricted_feature",
        "-swift.cannot_disable_feature",
    ],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_disallowed_enable_by_allowlist",
    feature_allowlists = [":allowlist_other_pkg"],
    features = [
        "swift.restricted_feature",
    ],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_disallowed_disable_by_allowlist",
    feature_allowlists = [":allowlist_other_pkg"],
    features = [
        "-swift.cannot_disable_feature",
    ],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_overlapping_allowlists_allowed",
    feature_allowlists = [
        ":allowlist_matching_pkg",
        ":allowlist_matching_subpackages",
    ],
    features = [
        "swift.restricted_feature",
    ],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_overlapping_allowlists_disallowed",
    feature_allowlists = [
        ":allowlist_matching_pkg",
        ":allowlist_other_pkg",
    ],
    features = [
        "swift.restricted_feature",
    ],
    tags = FIXTURE_TAGS,
)

passive_feature_fixture(
    name = "passive_fixture_for_aspect",
    feature_allowlists = [":allowlist_with_aspect_id"],
    features = [
        "swift.restricted_feature",
    ],
    tags = FIXTURE_TAGS,
)

apply_feature_configuration_test_aspect(
    name = "fixture_allowed_via_aspect_id",
    tags = FIXTURE_TAGS,
    target = ":passive_fixture_for_aspect",
)

# -----------------------------------------------------------------------------
# Library targets for testing `per_module_swiftcopt` and `copt`.

swift_library(
    name = "target_a",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "target_b",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

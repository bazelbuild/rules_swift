load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load("//test/rules:feature_configuration_test.bzl", "feature_configuration_test_fixture")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

feature_configuration_test_fixture(
    name = "fixture_with_direct_internal_feature",
    features = [
        "swift._internal_feature",
    ],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_with_direct_disabled_internal_feature",
    features = [
        "-swift._internal_feature",
    ],
    tags = FIXTURE_TAGS,
)

feature_configuration_test_fixture(
    name = "fixture_with_additional_internal_feature",
    additional_features = [
        "swift._internal_feature",
    ],
    tags = FIXTURE_TAGS,
)

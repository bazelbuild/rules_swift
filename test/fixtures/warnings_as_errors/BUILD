load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing warnings-as-errors features.

swift_library(
    name = "legacy_diagnostic_id",
    srcs = ["Empty.swift"],
    features = [
        "swift.werror.access_control_ext_member_more",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "warning_group",
    srcs = ["Empty.swift"],
    features = [
        "swift.werror.DeprecatedDeclaration",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "mixed_diagnostic_and_group",
    srcs = ["Empty.swift"],
    features = [
        "swift.werror.access_control_ext_member_more",
        "swift.werror.DeprecatedDeclaration",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "disabled_features",
    srcs = ["Empty.swift"],
    features = [
        "-swift.werror.access_control_ext_member_more",
        "-swift.werror.DeprecatedDeclaration",
    ],
    tags = FIXTURE_TAGS,
)

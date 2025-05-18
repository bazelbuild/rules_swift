load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing environment propagation of binaries and tests.

swift_binary(
    name = "binary",
    srcs = ["Binary.swift"],
    env = {
        "TEST_ENV_VAR": "test-value",
    },
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "test",
    srcs = ["Test.swift"],
    env = {
        "TEST_ENV_VAR": "test-value",
    },
    env_inherit = ["HOME"],
    tags = FIXTURE_TAGS,
)

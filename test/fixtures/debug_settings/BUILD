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
# Fixtures for testing serializing debug options.

swift_library(
    name = "simple",
    srcs = ["Empty.swift"],
    features = [
        # TODO: b/351801556 - Remove this when it is the default on all
        # toolchains.
        "swift.compile_in_parallel",
    ],
    tags = FIXTURE_TAGS,
)

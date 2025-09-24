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

# TODO: The `default_no_split_args` split_derived_files_generation is not supported in parallel.
# We need to handle falling back to non-parallel compilation when this feature is enabled, but dont currently.
swift_library(
    name = "simple_batch_mode",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

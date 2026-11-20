load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)
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

swift_library(
    name = "simple_with_debug_module_path",
    srcs = ["Empty.swift"],
    features = [
        "swift.compile_in_parallel",
        "swift._supports_debug_module_path",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "simple_without_debug_module_path",
    srcs = ["Empty.swift"],
    features = [
        "swift.compile_in_parallel",
        "-swift._supports_debug_module_path",
    ],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "binary",
    tags = FIXTURE_TAGS,
    deps = [":simple"],
)

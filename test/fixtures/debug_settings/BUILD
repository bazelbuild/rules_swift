load("//swift:swift_binary.bzl", "swift_binary")
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
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "binary",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "module_path_binary",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":simple"],
)

# No sources of its own: debug modules must be collected from dependencies.
swift_binary(
    name = "private_deps_binary",
    tags = FIXTURE_TAGS,
    deps = [
        "//test/fixtures/private_deps:client_cc_deps",
        "//test/fixtures/private_deps:client_swift_deps",
    ],
)

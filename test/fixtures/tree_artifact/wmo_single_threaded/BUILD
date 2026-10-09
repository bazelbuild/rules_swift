load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

# Single-threaded whole-module optimization emits one object for the module.
swift_library(
    name = "tree_artifact",
    srcs = [
        "//test/fixtures/tree_artifact:Regular.swift",
        "//test/fixtures/tree_artifact:generated",
    ],
    copts = [
        "-wmo",
        "-num-threads",
        "0",
    ],
    module_name = "TreeArtifact",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "binary",
    srcs = ["//test/fixtures/tree_artifact:main.swift"],
    tags = FIXTURE_TAGS,
    deps = [":tree_artifact"],
)

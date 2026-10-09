load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

# Multithreaded whole-module optimization emits one object per source.
swift_library(
    name = "tree_artifact",
    srcs = [
        "//test/fixtures/tree_artifacts:Regular.swift",
        "//test/fixtures/tree_artifacts:generated",
    ],
    copts = ["-wmo"],
    module_name = "TreeArtifact",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "binary",
    srcs = ["//test/fixtures/tree_artifacts:main.swift"],
    tags = FIXTURE_TAGS,
    deps = [":tree_artifact"],
)

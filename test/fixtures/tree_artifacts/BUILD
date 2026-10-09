load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":rules.bzl", "generate_swift_tree_artifact")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################

generate_swift_tree_artifact(
    name = "dynamic_sources",
)

generate_swift_tree_artifact(
    name = "sources_without_extension",
    directory_name = "GeneratedSources",
)

swift_library(
    name = "with_tree_artifact_without_extension",
    srcs = [":sources_without_extension"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_tree_artifact",
    srcs = [":dynamic_sources"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_tree_artifact_and_static",
    srcs = [
        "Static.swift",
        ":dynamic_sources",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_tree_artifact_wmo",
    srcs = [":dynamic_sources"],
    copts = ["-wmo"],
    tags = FIXTURE_TAGS,
)

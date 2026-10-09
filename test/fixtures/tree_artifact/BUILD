load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":generate_swift_directory.bzl", "generate_swift_directory")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

generate_swift_directory(
    name = "generated",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "tree_artifact",
    srcs = [
        "Regular.swift",
        ":generated",
    ],
    module_name = "TreeArtifact",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "tree_artifact_binary",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
    deps = [":tree_artifact"],
)

sh_test(
    name = "tree_artifact_test",
    srcs = ["tree_artifact_test.sh"],
    args = ["$(rootpath :tree_artifact_binary)"],
    data = [":tree_artifact_binary"],
)

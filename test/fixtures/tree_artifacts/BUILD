load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift_binary.bzl", "swift_binary")
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load("//swift:swift_test.bzl", "swift_test")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":rules.bzl", "generate_swift_directory", "generate_swift_tree_artifact")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

exports_files([
    "Regular.swift",
    "main.swift",
])

###############################################################################

generate_swift_tree_artifact(
    name = "dynamic_sources",
)

write_file(
    name = "quoted_source",
    out = "Quoted\"Source.swift",
    content = ["public struct QuotedSource {}"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_quoted_source",
    srcs = [":quoted_source"],
    tags = FIXTURE_TAGS,
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

# Binaries and tests built from tree artifacts, which are run by
# `tree_artifact_test` and `tree_artifact_swift_test`.

generate_swift_directory(
    name = "generated",
    srcs = {
        "Generated.swift": "public struct Generated { public init() {} }",
        "Nested/Nested.swift": "public let nestedValue = 41",
    },
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

generate_swift_directory(
    name = "generated_main",
    srcs = {
        "Greeting.swift": "let greeting = \"Generated 42\"",
        "main.swift": "print(greeting)",
    },
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "tree_artifact_main_binary",
    srcs = [":generated_main"],
    tags = FIXTURE_TAGS,
)

sh_test(
    name = "tree_artifact_test",
    srcs = ["tree_artifact_test.sh"],
    args = [
        "$(rootpath :tree_artifact_binary)",
        "$(rootpath :tree_artifact_main_binary)",
        "$(rootpath //test/fixtures/tree_artifacts/wmo:binary)",
        "$(rootpath //test/fixtures/tree_artifacts/wmo_single_threaded:binary)",
    ],
    data = [
        ":tree_artifact_binary",
        ":tree_artifact_main_binary",
        "//test/fixtures/tree_artifacts/wmo:binary",
        "//test/fixtures/tree_artifacts/wmo_single_threaded:binary",
    ],
)

generate_swift_directory(
    name = "generated_tests",
    srcs = {
        "GeneratedTests.swift": """\
import TreeArtifact
import XCTest

final class GeneratedTests: XCTestCase {
  func testGenerated() {
    XCTAssertEqual(describe(Generated()), "Generated 42")
  }
}""",
    },
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "tree_artifact_swift_test",
    srcs = [":generated_tests"],
    deps = [":tree_artifact"],
)

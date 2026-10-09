load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":generate_swift_directory.bzl", "generate_swift_directory")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

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

# A binary whose only source is a directory, including `main.swift`, so its own
# objects come from a directory and no `-parse-as-library` is added.
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
    ],
    data = [
        ":tree_artifact_binary",
        ":tree_artifact_main_binary",
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

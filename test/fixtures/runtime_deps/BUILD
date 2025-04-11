load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

exports_files(["transitive_data.txt"])

swift_library(
    name = "transitive_library",
    srcs = ["transitive_library.swift"],
    data = [":transitive_data.txt"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "direct_library",
    srcs = ["direct_library.swift"],
    tags = FIXTURE_TAGS,
    deps = [":transitive_library"],
)

swift_binary(
    name = "runtime_deps",
    srcs = ["main.swift"],
    module_name = "binary",
    tags = FIXTURE_TAGS,
    deps = [":direct_library"],
)

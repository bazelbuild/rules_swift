load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

exports_files(["data.txt"])

swift_library(
    name = "library",
    srcs = ["library.swift"],
    data = [":data.txt"],
    module_name = "library",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "runtime_deps",
    srcs = ["main.swift"],
    module_name = "binary",
    tags = FIXTURE_TAGS,
    deps = [":library"],
)

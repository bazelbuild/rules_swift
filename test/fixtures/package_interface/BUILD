load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_testonly = True,
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "package_swiftinterface_library",
    package_name = "ExamplePackage",
    srcs = ["Library.swift"],
    library_evolution = True,
    module_name = "PackageLibrary",
    tags = FIXTURE_TAGS,
)

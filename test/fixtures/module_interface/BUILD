load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_import.bzl", "swift_import")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_testonly = True,
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_binary(
    name = "client",
    srcs = ["Client.swift"],
    tags = FIXTURE_TAGS,
    deps = [":toy_module"],
)

swift_binary(
    name = "transitive_client",
    srcs = ["TransitiveClient.swift"],
    tags = FIXTURE_TAGS,
    deps = [":dependent_toy_module"],
)

swift_import(
    name = "dependent_toy_module",
    archives = [
        "//test/fixtures/module_interface/library:toy_outputs/libDependentToyModule.a",
    ],
    module_name = "DependentToyModule",
    swiftdoc = "//test/fixtures/module_interface/library:toy_outputs/DependentToyModule.swiftdoc",
    swiftinterface = "//test/fixtures/module_interface/library:toy_outputs/DependentToyModule.swiftinterface",
    tags = FIXTURE_TAGS,
    deps = [":toy_module"],
)

swift_import(
    name = "toy_module",
    archives = [
        "//test/fixtures/module_interface/library:toy_outputs/libToyModule.a",
    ],
    module_name = "ToyModule",
    swiftdoc = "//test/fixtures/module_interface/library:toy_outputs/ToyModule.swiftdoc",
    swiftinterface = "//test/fixtures/module_interface/library:toy_outputs/ToyModule.swiftinterface",
    tags = FIXTURE_TAGS,
)

load(
    "//swift:swift.bzl",
    "swift_binary",
    "swift_import",
    "swift_library",
)
load(
    "//test/fixtures:common.bzl",
    "FIXTURE_TAGS",
)
load(
    "//test/rules:swift_library_artifact_collector.bzl",
    "swift_library_artifact_collector",
)

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

swift_import(
    name = "toy_module",
    archives = [":toy_outputs/libToyModule.a"],
    module_name = "ToyModule",
    swiftdoc = ":toy_outputs/ToyModule.swiftdoc",
    swiftinterface = ":toy_outputs/ToyModule.swiftinterface",
    tags = FIXTURE_TAGS,
)

# Checking in pre-built artifacts like a `.swiftinterface` and static libraries
# would require different artifacts for every platform the test might run on.
# Instead, build it on-demand but forward the outputs using the "artifact
# collector" rule below to make them act as if they were pre-built outputs when
# referenced by the `swift_import` rule.

swift_library(
    name = "toy_module_library",
    srcs = ["ToyModule.swift"],
    module_name = "ToyModule",
    tags = FIXTURE_TAGS,
)

swift_library_artifact_collector(
    name = "toy_module_artifact_collector",
    static_library = "toy_outputs/libToyModule.a",
    swiftdoc = "toy_outputs/ToyModule.swiftdoc",
    swiftinterface = "toy_outputs/ToyModule.swiftinterface",
    tags = FIXTURE_TAGS,
    target = ":toy_module_library",
    target_compatible_with = ["@platforms//os:macos"],
)

load("//swift:swift_library.bzl", "swift_library")
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

# Checking in pre-built artifacts like a `.swiftinterface` and static libraries
# would require different artifacts for every platform the test might run on.
# Instead, build it on-demand but forward the outputs using the "artifact
# collector" rule below to make them act as if they were pre-built outputs when
# referenced by the `swift_import` rule.
#
# These must be in a separate package than the `swift_import` target because
# that rule propagates its pre-built inputs in `DefaultInfo`.

swift_library(
    name = "toy_module_consumer",
    srcs = ["ToyConsumer.swift"],
    library_evolution = True,
    module_name = "ToyModuleConsumer",
    tags = FIXTURE_TAGS,
    deps = ["//test/fixtures/module_interface/library:toy_module_library"],
)

swift_library_artifact_collector(
    name = "toy_module_consumer_artifact_collector",
    static_library = "toy_consumer_outputs/libToyModuleConsumer.a",
    swiftdoc = "toy_consumer_outputs/ToyModuleConsumer.swiftdoc",
    swiftinterface = "toy_consumer_outputs/ToyModuleConsumer.swiftinterface",
    tags = FIXTURE_TAGS,
    target = ":toy_module_consumer",
    target_compatible_with = ["@platforms//os:macos"],
)

swift_library(
    name = "toy_module_consumer_without_library_evolution",
    srcs = ["ToyConsumer.swift"],
    library_evolution = False,
    module_name = "ToyModuleConsumerNoEvolution",
    tags = FIXTURE_TAGS,
)

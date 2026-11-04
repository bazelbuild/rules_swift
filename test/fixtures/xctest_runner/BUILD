load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load("//test:transitions.bzl", "transition_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing xctest_runner outputs

swift_test(
    name = "PassingUnitTests",
    srcs = ["PassingUnitTests.swift"],
    tags = FIXTURE_TAGS,
)

transition_binary(
    name = "PassingUnitTests_macos_11_0",
    testonly = True,
    macos_minimum_os = "11.0",
    tags = FIXTURE_TAGS,
    target = ":PassingUnitTests",
    target_compatible_with = ["@platforms//os:macos"],
    # Recent Xcode versions ship XCTest support libraries built for macOS 14,
    # which produce a linker warning at this deployment target.
    transitive_features = ["-treat_warnings_as_errors"],
)

swift_test(
    name = "FailingUnitTests",
    srcs = ["FailingUnitTests.swift"],
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "EmptyUnitTests",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "MainLibrary",
    srcs = ["MainLibrary.swift"],
    module_name = "MainLibrary",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "MainLibraryApp",
    tags = FIXTURE_TAGS,
    deps = [":MainLibrary"],
)

swift_test(
    name = "MainLibraryTests",
    srcs = ["MainLibraryTests.swift"],
    tags = FIXTURE_TAGS,
    deps = [":MainLibrary"],
)

swift_library(
    name = "MainLibraryTestCases",
    testonly = True,
    srcs = ["MainLibraryTests.swift"],
    tags = FIXTURE_TAGS,
    deps = [":MainLibrary"],
)

swift_test(
    name = "MainLibraryTestsWithoutSources",
    module_name = "MainLibraryTestsWithoutSources",
    tags = FIXTURE_TAGS,
    deps = [":MainLibraryTestCases"],
)

swift_test(
    name = "MainLibraryManualRunner",
    discover_tests = False,
    tags = FIXTURE_TAGS,
    deps = [":MainLibrary"],
)

swift_test(
    name = "FailingSwiftTestingTests",
    srcs = ["FailingSwiftTestingTests.swift"],
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "EmptySwiftTestingSuite",
    srcs = ["EmptySwiftTestingSuite.swift"],
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "PassingSwiftTestingTests",
    srcs = ["PassingSwiftTestingTests.swift"],
    tags = FIXTURE_TAGS,
)

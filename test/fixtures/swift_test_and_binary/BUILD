load("//swift:swift_binary.bzl", "swift_binary")
load(
    "//swift:swift_extract_symbol_graph.bzl",
    "swift_extract_symbol_graph",
)
load("//swift:swift_import.bzl", "swift_import")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load(
    "//test/fixtures:common.bzl",
    "FIXTURE_TAGS",
)

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing `swift_test` discovery modes.

swift_library(
    name = "testonly_lib",
    testonly = True,
    srcs = ["Empty.swift"],
    module_name = "TestOnlyLib",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "non_testonly_lib",
    testonly = False,
    srcs = ["Empty.swift"],
    module_name = "NonTestOnlyLib",
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "test_with_srcs",
    srcs = ["Empty.swift"],
    module_name = "TestWithSrcs",
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "test_without_srcs_with_testonly_dep",
    tags = FIXTURE_TAGS,
    deps = [":testonly_lib"],
)

swift_test(
    name = "test_with_discover_tests_false",
    srcs = ["Empty.swift"],
    discover_tests = False,
    module_name = "TestNoDiscovery",
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "test_without_srcs_no_test_modules",
    tags = FIXTURE_TAGS,
    deps = [":non_testonly_lib"],
)

###############################################################################
# Fixtures for testing `swift_binary` entry-point renaming and `SwiftBinaryInfo`.

swift_binary(
    name = "binary_with_srcs",
    srcs = ["Empty.swift"],
    module_name = "MyBinary",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "binary_without_srcs",
    tags = FIXTURE_TAGS,
    deps = [":non_testonly_lib"],
)

###############################################################################
# Fixtures for testing `swift_library` `-parse-as-library` vs `main.swift`.

swift_library(
    name = "lib_without_main",
    srcs = ["Empty.swift"],
    module_name = "LibWithoutMain",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "lib_with_main",
    srcs = ["main.swift"],
    module_name = "LibWithMain",
    tags = FIXTURE_TAGS,
)

###############################################################################
# Fixtures for testing rule validation failures.

swift_library(
    name = "lib_overlapping_deps",
    srcs = ["Empty.swift"],
    private_deps = [":non_testonly_lib"],
    tags = FIXTURE_TAGS,
    deps = [":non_testonly_lib"],
)

swift_library(
    name = "lib_no_swift_srcs",
    srcs = ["empty.c"],
    tags = FIXTURE_TAGS,
)

swift_import(
    name = "import_missing_module_and_interface",
    module_name = "MissingModule",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "dup_some_module",
    testonly = True,
    srcs = ["Empty.swift"],
    module_name = "SomeModule",
    tags = FIXTURE_TAGS,
)

swift_extract_symbol_graph(
    name = "symbol_graph_duplicate_modules",
    testonly = True,
    tags = FIXTURE_TAGS,
    targets = [
        ":dup_some_module",
        "//test/fixtures/symbol_graphs:some_module",
    ],
)

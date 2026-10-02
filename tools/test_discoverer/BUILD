load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)
load(
    "//swift:swift_extract_symbol_graph.bzl",
    "swift_extract_symbol_graph",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
)

swift_binary(
    name = "test_discoverer",
    srcs = [
        "DiscoveredTests.swift",
        "SymbolCollector.swift",
        "SymbolGraphTestPrinter.swift",
        "SymbolKitExtensions.swift",
        "TestDiscoverer.swift",
        "TestPrinterCommon.swift",
    ],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "fixture_tests",
    testonly = True,
    srcs = ["FixtureTests.swift"],
    target_compatible_with = select({
        "@build_bazel_apple_support//constraints:apple": [
            "@platforms//:incompatible",
        ],
        "//conditions:default": [],
    }),
)

swift_extract_symbol_graph(
    name = "fixture_symbol_graphs",
    testonly = True,
    minimum_access_level = "internal",
    target_compatible_with = select({
        "@build_bazel_apple_support//constraints:apple": [
            "@platforms//:incompatible",
        ],
        "//conditions:default": [],
    }),
    targets = [":fixture_tests"],
)

swift_test(
    name = "test_discoverer_test",
    srcs = ["TestDiscovererTests.swift"],
    data = [":fixture_symbol_graphs"],
    target_compatible_with = select({
        "@build_bazel_apple_support//constraints:apple": [
            "@platforms//:incompatible",
        ],
        "//conditions:default": [],
    }),
    deps = [
        ":test_discoverer",
    ],
)

load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)

package(
    features = ["swift.enable_v6"],
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

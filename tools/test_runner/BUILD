load(
    "//swift:swift_library.bzl",
    "swift_library",
)

swift_library(
    name = "test_runner",
    testonly = 1,
    srcs = [
        "BazelXMLTestObserver.swift",
        "Concurrency.swift",
        "JSON.swift",
        "LinuxXCTestRunner.swift",
        "Locked.swift",
        "ObjectiveCXCTestRunner.swift",
        "ShardingFilteringTestCollector.swift",
        "StringInterpolation+XMLEscaping.swift",
        "SwiftTestingRunner.swift",
        "TestRunnerMain.swift",
        "XUnitTestRecorder.swift",
    ],
    visibility = ["//visibility:public"],
)

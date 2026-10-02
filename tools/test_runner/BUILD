load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
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

swift_test(
    name = "test_runner_test",
    srcs = ["TestRunnerTests.swift"],
    deps = [
        ":test_runner",
    ],
)

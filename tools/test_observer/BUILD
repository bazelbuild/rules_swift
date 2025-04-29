load(
    "//swift:swift_library.bzl",
    "swift_library",
)

swift_library(
    name = "test_observer",
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
        "XUnitTestRecorder.swift",
    ],
    module_name = "BazelTestObservation",
    visibility = ["//visibility:public"],
)

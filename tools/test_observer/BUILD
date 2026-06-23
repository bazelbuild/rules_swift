load(
    "//swift:swift_library.bzl",
    "swift_library",
)

swift_library(
    name = "test_observer",
    testonly = True,
    srcs = [
        "BazelXMLTestObserver.swift",
        "Concurrency.swift",
        "JSON.swift",
        "Locked.swift",
        "ObjectiveCXCTestRunner.swift",
        "ShardingFilteringTestCollector.swift",
        "StringInterpolation+XMLEscaping.swift",
        "SwiftCorelibsXCTestRunner.swift",
        "SwiftTestingRunner.swift",
        "XUnitTestRecorder.swift",
    ],
    module_name = "BazelTestObservation",
    visibility = ["//visibility:public"],
)

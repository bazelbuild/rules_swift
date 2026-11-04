load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
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

swift_test(
    name = "swift_testing_runner_test",
    srcs = ["SwiftTestingRunnerTests.swift"],
    target_compatible_with = select({
        "@platforms//os:windows": ["@platforms//:incompatible"],
        "//conditions:default": [],
    }),
    deps = [":test_observer"],
)

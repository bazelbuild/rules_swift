load(
    "//swift:swift_library.bzl",
    "swift_library",
)

swift_library(
    name = "test_observer",
    testonly = 1,
    srcs = [
        "BazelXMLTestObserver.swift",
        "BazelXMLTestObserverRegistration.swift",
        "Locked.swift",
        "StringInterpolation+XMLEscaping.swift",
        "XUnitTestRecorder.swift",
    ],
    module_name = "BazelTestObservation",
    visibility = ["//visibility:public"],
)

load("//swift:swift.bzl", "swift_test")

licenses(["notice"])

swift_test(
    name = "xctest",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
)

swift_test(
    name = "xctest_tsan",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    features = ["tsan"],
)

swift_test(
    name = "xctest_asan",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    features = ["asan"],
)

swift_test(
    name = "xctest_ubsan",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    features = ["ubsan"],
)

swift_test(
    name = "xctest_tsan_and_ubsan",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    features = [
        "tsan",
        "ubsan",
    ],
)

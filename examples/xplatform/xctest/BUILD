load(
    "//swift:swift_test.bzl",
    "swift_test",
)

package(
    features = ["swift.enable_v6"],
)

licenses(["notice"])

swift_test(
    name = "xctest",
    srcs = ["SimpleTests.swift"],
    features = ["-swift.enable_v6"],
)

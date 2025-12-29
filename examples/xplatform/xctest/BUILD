load(
    "//swift:swift_test.bzl",
    "swift_test",
)

licenses(["notice"])

swift_test(
    name = "xctest",
    srcs = ["SimpleTests.swift"],
    features = ["-swift.enable_v6"],  # b/472257384
)

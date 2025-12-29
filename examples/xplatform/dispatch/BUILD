load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)

licenses(["notice"])

swift_binary(
    name = "dispatch",
    srcs = ["main.swift"],
    features = ["-swift.enable_v6"],  # b/472257384
)

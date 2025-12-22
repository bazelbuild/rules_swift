load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)

package(
    features = ["swift.enable_v6"],
)

licenses(["notice"])

swift_binary(
    name = "dispatch",
    srcs = ["main.swift"],
    features = ["-swift.enable_v6"],
)

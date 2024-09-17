load("//swift:swift.bzl", "swift_binary")

swift_binary(
    name = "binary",
    srcs = ["main.swift"],
    deps = [
        "//swift/runfiles",
    ],
    data = [
        "data/sample.txt",
    ],
    visibility = ["//visibility:public"],
)
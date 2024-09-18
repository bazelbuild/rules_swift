load("//swift:swift.bzl", "swift_binary")

swift_binary(
    name = "binary",
    srcs = ["main.swift"],
    data = [
        "data/sample.txt",
    ],
    visibility = ["//visibility:public"],
    deps = [
        "//swift/runfiles",
    ],
)

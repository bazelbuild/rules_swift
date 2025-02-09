load("@build_bazel_rules_swift//swift:swift.bzl", "swift_binary")

swift_binary(
    name = "runfiles",
    srcs = ["main.swift"],
    data = [
        "data/sample.txt",
    ],
    visibility = ["//visibility:public"],
    deps = [
        "//swift/runfiles",
    ],
)

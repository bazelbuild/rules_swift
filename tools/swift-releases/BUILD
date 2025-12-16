load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

swift_binary(
    name = "swift-releases",
    srcs = ["SwiftReleases.swift"],
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_apple_swift_argument_parser//:ArgumentParser",
    ],
)

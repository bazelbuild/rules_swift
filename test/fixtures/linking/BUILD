load("//swift:swift.bzl", "swift_binary")
load(":fake_framework.bzl", "fake_framework")

package(
    default_visibility = ["//test:__subpackages__"],
)

fake_framework(
    name = "framework",
)

swift_binary(
    name = "bin",
    srcs = ["main.swift"],
    deps = [":framework"],
)

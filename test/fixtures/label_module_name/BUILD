load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
)

package(
    default_visibility = [
        "//test:__subpackages__",
    ],
)

licenses(["notice"])

swift_library(
    name = "child",
    srcs = ["child.swift"],
    features = ["swift.label_as_module_name"],
    tags = ["manual"],
)

swift_library(
    name = "label_module_name",
    srcs = ["main.swift"],
    features = ["swift.label_as_module_name"],
    tags = ["manual"],
    deps = [":child"],
)

swift_test(
    name = "test_with_srcs",
    srcs = ["test.swift"],
    features = ["swift.label_as_module_name"],
    deps = [
        ":child",
    ],
)

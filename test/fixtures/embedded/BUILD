load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//test/fixtures:common.bzl",
    "FIXTURE_TAGS",
)

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "dual_mode_library",
    srcs = [
        "First.swift",
        "Second.swift",
    ],
    features = [
        "swift.compile_in_parallel",
        "swift.enable_batch_mode",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "via_experimental_feature",
    srcs = [
        "First.swift",
        "Second.swift",
    ],
    features = [
        "swift.compile_in_parallel",
        "swift.enable_batch_mode",
        "swift.experimental.Embedded",
        "swift.opt_uses_wmo",
    ],
    tags = FIXTURE_TAGS,
)

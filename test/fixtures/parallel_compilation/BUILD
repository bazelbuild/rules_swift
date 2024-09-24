load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
    features = ["swift.compile_in_parallel"],
)

licenses(["notice"])

###############################################################################

swift_library(
    name = "no_opt_no_wmo",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "no_opt_with_wmo",
    srcs = ["Empty.swift"],
    copts = ["-wmo"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_opt_no_wmo",
    srcs = ["Empty.swift"],
    copts = ["-O"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_opt_with_wmo",
    srcs = ["Empty.swift"],
    copts = [
        "-O",
        "-wmo",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "onone_with_wmo",
    srcs = ["Empty.swift"],
    copts = [
        "-Onone",
        "-wmo",
    ],
    tags = FIXTURE_TAGS,
)

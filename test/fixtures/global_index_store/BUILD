load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

swift_library(
    name = "simple",
    srcs = [
        "first.swift",
        "second.swift",
    ],
    features = [
        "swift.use_global_index_store",
        "swift.index_while_building",
    ],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
)

filegroup(
    name = "indexstore",
    srcs = [":compressed"],
    output_group = "swift_index_store",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "compressed",
    srcs = [
        "first.swift",
        "second.swift",
    ],
    features = [
        "swift.index_while_building",
        "swift.index_store_compress",
        "swift.use_global_index_store",
    ],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
)

exports_files(["check_compressed_index.sh"])

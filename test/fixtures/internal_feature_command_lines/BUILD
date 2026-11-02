load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

# Internal features are intentionally overridden here to test command lines
# for toolchain capabilities that may differ from the host's defaults.
swift_library(
    name = "unsupported_developer_dir",
    srcs = ["Empty.swift"],
    features = ["-swift._supports_developer_dir"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "const_values_frontend_flag",
    srcs = ["Empty.swift"],
    features = ["-swift._supports_const_gather_protocols_list"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "const_values_driver_flag",
    srcs = ["Empty.swift"],
    features = ["swift._supports_const_gather_protocols_list"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "multiple_files",
    srcs = [
        "Empty.swift",
        "Empty2.swift",
    ],
    features = ["swift._supports_const_gather_protocols_list"],
    generates_header = False,
    tags = FIXTURE_TAGS,
)

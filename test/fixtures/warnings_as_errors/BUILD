load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

# NOTE: Can be used to test that this feature still causes failures
swift_library(
    name = "forced_downcast_noop",
    srcs = ["ForcedDowncastNoop.swift"],
    features = ["swift.werror.forced_downcast_noop"],
    tags = FIXTURE_TAGS,
)

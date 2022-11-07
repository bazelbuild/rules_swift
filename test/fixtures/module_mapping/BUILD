load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_module_mapping.bzl", "swift_module_mapping")
load(
    "//test/fixtures:common.bzl",
    "FIXTURE_TAGS",
)
load(":apply_mapping.bzl", "apply_mapping")

package(
    default_testonly = True,
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "Common",
    srcs = ["Common.swift"],
    module_name = "Common",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "MySDK",
    srcs = ["MySDK.swift"],
    module_name = "MySDK",
    tags = FIXTURE_TAGS,
    deps = [":Common"],
)

swift_module_mapping(
    name = "MySDK_module_mapping",
    # This must not be testonly because it is used by the toolchain through the
    # `:module_mapping` label flag.
    testonly = False,
    aliases = {
        "Common": "MySDKInternal_Common",
    },
)

# This is the target that will be tested in `module_mapping.bzl`, to force the
# `MySDK` target to build in a configuration that sets the flag.
apply_mapping(
    name = "MySDK_with_mapping",
    mapping = ":MySDK_module_mapping",
    target = ":MySDK",
)

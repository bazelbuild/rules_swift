load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//test:transitions.bzl", "transition_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

swift_interop_hint(
    name = "Defines_hint",
    module_name = "Defines",
    tags = FIXTURE_TAGS,
)

swift_interop_hint(
    name = "NoCoptsTokenization_hint",
    module_name = "NoCoptsTokenization",
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "Defines",
    srcs = [
        "Defines.c",
        "Defines.h",
    ],
    hdrs = ["Defines.h"],
    aspect_hints = [":Defines_hint"],
    copts = [
        "-DFIXTURE_FROM_COPTS=1",
        "-DFIXTURE_FROM_COPTS_WITH_SPACES=rules\\ swift\\ fixture",
        "-DFIXTURE_FROM_QUOTED_COPTS='quoted rules swift fixture'",
        "-include$(location :Defines.h)",
    ],
    local_defines = ["FIXTURE_FROM_LOCAL_DEFINES=1"],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "NoCoptsTokenization",
    srcs = [
        "NoCoptsTokenization.c",
        "NoCoptsTokenization.h",
    ],
    hdrs = ["NoCoptsTokenization.h"],
    aspect_hints = [":NoCoptsTokenization_hint"],
    copts = ["-DFIXTURE_NO_COPTS_TOKENIZATION=rules swift fixture"],
    features = ["no_copts_tokenization"],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "user",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
    deps = [
        ":Defines",
        ":NoCoptsTokenization",
    ],
)

transition_binary(
    name = "user_explicit_modules",
    tags = FIXTURE_TAGS,
    target = ":user",
    # TODO: Remove when we support explicit modules on Linux
    target_compatible_with = ["@platforms//os:macos"],
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
    ],
)

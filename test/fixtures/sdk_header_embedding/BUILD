load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//swift:swift_library.bzl", "swift_library")
load("//test:transitions.bzl", "transition_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

swift_interop_hint(
    name = "SDKHeaders_hint",
    module_name = "SDKHeaders",
)

cc_library(
    name = "SDKHeaders",
    hdrs = ["SDKHeaders.h"],
    aspect_hints = [":SDKHeaders_hint"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "consumer",
    srcs = ["Consumer.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":SDKHeaders",
        "@system_sdk//:Foundation",
    ],
)

transition_binary(
    name = "consumer_explicit",
    tags = FIXTURE_TAGS,
    target = ":consumer",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
        "swift.use_explicit_swift_module_map",
        "swift.index_while_building",
        # Model SDK includes in vendored/generated headers without strict
        # module ownership checks.
        "-swift.layering_check_for_c_deps",
    ],
)

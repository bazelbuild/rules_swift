load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//swift:swift_library.bzl", "swift_library")
load("//test:transitions.bzl", "transition_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":fixtures.bzl", "cc_inc_library", "legacy_precompile", "pcm_files")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

cc_library(
    name = "leaf",
    hdrs = ["leaf.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "middle",
    hdrs = ["include/middle.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":leaf"],
)

cc_library(
    name = "top",
    hdrs = ["top.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":middle"],
)

cc_library(
    name = "system",
    hdrs = ["top.h"],
    aspect_hints = ["//swift:auto_module"],
    features = ["swift.system_module"],
    tags = FIXTURE_TAGS,
    deps = [":middle"],
)

# Reuse the middle header with alternative classifications in independent
# dependency graphs, each with a consumer that includes it through top.h.
cc_library(
    name = "textual",
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    textual_hdrs = ["include/middle.h"],
    deps = [":leaf"],
)

swift_interop_hint(
    name = "excluded_hint",
    exclude_hdrs = ["include/middle.h"],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "excluded",
    hdrs = ["include/middle.h"],
    aspect_hints = [":excluded_hint"],
    tags = FIXTURE_TAGS,
    deps = [":leaf"],
)

# An umbrella-directory map also covers the client-provided module-map case.
swift_interop_hint(
    name = "custom_hint",
    module_map = "custom.modulemap",
    module_name = "Custom",
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "custom",
    hdrs = ["include/middle.h"],
    aspect_hints = [":custom_hint"],
    tags = FIXTURE_TAGS,
    deps = [":leaf"],
)

cc_inc_library(
    name = "inc",
    hdrs = ["include/middle.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":leaf"],
)

cc_library(
    name = "textual_consumer",
    hdrs = ["top.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":textual"],
)

cc_library(
    name = "excluded_consumer",
    hdrs = ["top.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":excluded"],
)

cc_library(
    name = "custom_consumer",
    hdrs = ["top.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":custom"],
)

cc_library(
    name = "inc_consumer",
    hdrs = ["top.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":inc"],
)

swift_library(
    name = "pure",
    srcs = ["Empty.swift"],
    generates_header = False,
    tags = FIXTURE_TAGS,
    deps = [":top"],
)

swift_library(
    name = "consumer",
    srcs = ["Empty.swift"],
    generates_header = False,
    tags = FIXTURE_TAGS,
    deps = [":pure"],
)

swift_library(
    name = "generated",
    srcs = ["Empty.swift"],
    generates_header = True,
    tags = FIXTURE_TAGS,
    deps = [":top"],
)

cc_library(
    name = "through_pure",
    hdrs = ["empty.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":pure"],
)

legacy_precompile(
    name = "legacy",
    hdrs = ["top.h"],
    module_map = "legacy.modulemap",
    tags = FIXTURE_TAGS,
    deps = [":middle"],
)

cc_library(
    name = "legacy_consumer",
    hdrs = ["empty.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":legacy"],
)

pcm_files(
    name = "pcm_files",
    tags = FIXTURE_TAGS,
    deps = [
        ":custom_consumer",
        ":excluded_consumer",
        ":inc_consumer",
        ":legacy_consumer",
        ":textual_consumer",
        ":top",
    ],
)

transition_binary(
    name = "pruned_pcms",
    tags = FIXTURE_TAGS,
    target = ":pcm_files",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.layering_check_for_c_deps",
        "-swift.add_default_precompiled_modules",
    ],
)

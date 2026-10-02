load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//mixed_language:mixed_language_library.bzl", "mixed_language_library")
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

# Reuse the middle header as a textual header in an independent dependency graph.
cc_library(
    name = "textual",
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    textual_hdrs = ["include/middle.h"],
    deps = [":leaf"],
)

swift_interop_hint(
    name = "excluded_hint",
    exclude_hdrs = ["excluded_extra.h"],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "excluded",
    hdrs = [
        "excluded.h",
        "excluded_extra.h",
    ],
    aspect_hints = [":excluded_hint"],
    tags = FIXTURE_TAGS,
    deps = [":middle"],
)

swift_interop_hint(
    name = "custom_hint",
    module_map = "custom.modulemap",
    module_name = "custom",
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "custom",
    hdrs = ["custom.h"],
    aspect_hints = [":custom_hint"],
    tags = FIXTURE_TAGS,
    deps = [":middle"],
)

swift_interop_hint(
    name = "umbrella_hint",
    module_map = "umbrella.modulemap",
    module_name = "Umbrella",
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "umbrella",
    hdrs = [
        "umbrella.h",
        "umbrella_headers/member.h",
    ],
    aspect_hints = [":umbrella_hint"],
    tags = FIXTURE_TAGS,
    deps = [":middle"],
)

cc_library(
    name = "umbrella_consumer",
    hdrs = ["umbrella_consumer.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":umbrella"],
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
    hdrs = ["excluded_consumer.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    deps = [":excluded"],
)

cc_library(
    name = "custom_consumer",
    hdrs = ["custom_consumer.h"],
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
        ":umbrella_consumer",
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

# The custom map marks middle.h textual, although it is a public hdrs entry.
# Consumers must retain its include closure through the mixed-language PCM.
mixed_language_library(
    name = "mixed",
    hdrs = [
        "empty.h",
        "include/middle.h",
    ],
    clang_srcs = [],
    # The generated Swift header has SDK includes without module-map use
    # declarations. Only the downstream consumer needs layering checks here.
    features = ["-swift.layering_check_for_c_deps"],
    module_map = "mixed.modulemap",
    module_name = "Mixed",
    swift_srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":leaf"],
)

cc_library(
    name = "mixed_consumer",
    hdrs = ["top.h"],
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":mixed"],
)

pcm_files(
    name = "mixed_pcm",
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":mixed_consumer"],
)

transition_binary(
    name = "mixed_pruned_pcm",
    tags = FIXTURE_TAGS,
    target = ":mixed_pcm",
    target_compatible_with = ["@platforms//os:macos"],
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.layering_check_for_c_deps",
        "swift.add_default_precompiled_modules",
    ],
)

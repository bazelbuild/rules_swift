load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "no_header",
    srcs = ["Empty.swift"],
    generates_header = False,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "auto_header",
    srcs = ["Empty.swift"],
    generates_header = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "explicit_header",
    srcs = ["Empty.swift"],
    generated_header_name = "SomeOtherName.h",
    generates_header = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "invalid_extension",
    srcs = ["Empty.swift"],
    generated_header_name = "Invalid.extension",
    generates_header = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "valid_path_separator",
    srcs = ["Empty.swift"],
    generated_header_name = "Valid/Separator.h",
    generates_header = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "invalid_attribute_combination",
    srcs = ["Empty.swift"],
    generated_header_name = "SomeOtherName.h",
    generates_header = False,
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "c_dependency",
    srcs = ["CDependency.m"],
    hdrs = ["CDependency.h"],
    aspect_hints = [":c_dependency_hint"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
)

swift_interop_hint(
    name = "c_dependency_hint",
    module_name = "GeneratedHeaderCDependency",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "generated_header_with_c_dep",
    srcs = ["UsesCDependency.swift"],
    generates_header = True,
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":c_dependency"],
)

objc_library(
    name = "objc_consumer_of_generated_header",
    srcs = ["ObjcConsumer.m"],
    enable_modules = True,
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":generated_header_with_c_dep"],
)

swift_library(
    name = "transitive_c_dependency",
    srcs = ["TransitiveCDependency.swift"],
    generates_header = True,
    module_name = "GeneratedHeaderTransitiveCDependency",
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":c_dependency"],
)

# This target uses only its direct Swift dependency. Its generated header must
# be able to import that dependency's header, including its Clang dependencies.
swift_library(
    name = "generated_header_with_transitive_c_dep",
    srcs = ["UsesTransitiveCDependency.swift"],
    generates_header = True,
    module_name = "GeneratedHeaderWithTransitiveCDep",
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":transitive_c_dependency"],
)

objc_library(
    name = "objc_consumer_of_generated_header_with_transitive_c_dep",
    srcs = ["TransitiveObjcConsumer.m"],
    enable_modules = True,
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":generated_header_with_transitive_c_dep"],
)

# Unlike the superclass above, a typealias doesn't need an Objective-C header
# of its own to re-export the C dependency's type.
swift_library(
    name = "headerless_c_dependency",
    srcs = ["HeaderlessCDependency.swift"],
    generates_header = False,
    module_name = "GeneratedHeaderHeaderlessCDependency",
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":c_dependency"],
)

swift_library(
    name = "generated_header_with_headerless_c_dep",
    srcs = ["UsesHeaderlessCDependency.swift"],
    generates_header = True,
    module_name = "GeneratedHeaderWithHeaderlessCDep",
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":headerless_c_dependency"],
)

objc_library(
    name = "objc_consumer_of_generated_header_with_headerless_c_dep",
    srcs = ["HeaderlessObjcConsumer.m"],
    enable_modules = True,
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":generated_header_with_headerless_c_dep"],
)

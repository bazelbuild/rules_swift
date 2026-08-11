load("//swift:swift_compiler_plugin.bzl", "swift_compiler_plugin")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing compiler plugin (macro) propagation

swift_compiler_plugin(
    name = "stringify_macro",
    srcs = [
        "StringifyMacro.swift",
        "StringifyMacroPlugin.swift",
    ],
    module_name = "StringifyMacroPlugin",
    tags = FIXTURE_TAGS,
    deps = [
        "@swift-syntax//:SwiftCompilerPlugin",
        "@swift-syntax//:SwiftSyntax",
        "@swift-syntax//:SwiftSyntaxBuilder",
        "@swift-syntax//:SwiftSyntaxMacroExpansion",
        "@swift-syntax//:SwiftSyntaxMacros",
    ],
)

swift_library(
    name = "stringify",
    srcs = ["Stringify.swift"],
    module_name = "Stringify",
    plugins = [":stringify_macro"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "stringify_user",
    srcs = ["StringifyUser.swift"],
    module_name = "StringifyUser",
    tags = FIXTURE_TAGS,
    deps = [":stringify"],
)

swift_library(
    name = "transitive_user",
    srcs = ["TransitiveUser.swift"],
    module_name = "TransitiveUser",
    tags = FIXTURE_TAGS,
    deps = [":stringify_user"],
)

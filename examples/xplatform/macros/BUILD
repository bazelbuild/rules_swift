load("//swift:swift.bzl", "swift_binary", "swift_library", "swift_test")
load("//swift:swift_compiler_plugin.bzl", "swift_compiler_plugin")

licenses(["notice"])

config_setting(
    name = "supports_macros",
    values = {"define": "supports_macros=1"},
)

swift_library(
    name = "stringify",
    srcs = ["Stringify.swift"],
    module_name = "Stringify",
    plugins = [":stringify_macro"],
)

swift_compiler_plugin(
    name = "stringify_macro",
    srcs = [
        "StringifyMacro.swift",
        "StringifyMacroPlugin.swift",
    ],
    module_name = "StringifyMacroPlugin",
    target_compatible_with = select({
        ":supports_macros": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [
        "@SwiftSyntax",
        "@SwiftSyntax//:SwiftCompilerPlugin",
        "@SwiftSyntax//:SwiftSyntaxBuilder",
        "@SwiftSyntax//:SwiftSyntaxMacros",
    ],
)

swift_binary(
    name = "stringify_client",
    srcs = ["StringifyClient.swift"],
    deps = [":stringify"],
)

swift_test(
    name = "stringify_macro_test",
    srcs = ["StringifyMacroTests.swift"],
    deps = [
        ":stringify_macro",
        "@SwiftSyntax",
        "@SwiftSyntax//:SwiftSyntaxBuilder",
        "@SwiftSyntax//:SwiftSyntaxMacros",
    ],
    target_compatible_with = select({
        ":supports_macros": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

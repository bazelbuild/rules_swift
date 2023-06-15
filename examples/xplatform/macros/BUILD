load("//swift:swift.bzl", "swift_binary", "swift_library", "swift_test")
load("//swift:swift_compiler_plugin.bzl", "swift_compiler_plugin")

licenses(["notice"])

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
)

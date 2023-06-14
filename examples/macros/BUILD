load("//swift:swift.bzl", "swift_binary", "swift_library", "swift_macro", "swift_test")

swift_test(
    name = "macrostests",
    srcs = [
        "macro.swift",
        "macrostests.swift",
    ],
    deps = [
        "@SwiftSyntax//:SwiftCompilerPlugin",
        "@SwiftSyntax//:SwiftSyntaxMacros",
        "@SwiftSyntax//:SwiftSyntaxMacrosTestSupport",
    ],
)

swift_macro(
    name = "macrosplugin",
    srcs = [
        "macro.swift",
        "plugin.swift",
    ],
    module_name = "macros",
    deps = [
        "@SwiftSyntax",
        "@SwiftSyntax//:SwiftCompilerPlugin",
        "@SwiftSyntax//:SwiftSyntaxMacros",
    ],
)

swift_library(
    name = "lib",
    srcs = ["lib.swift"],
    macros = [":macrosplugin"],
    module_name = "lib",
)

swift_binary(
    name = "main",
    srcs = ["main.swift"],
    deps = [":lib"],
)

load("//swift:swift.bzl", "swift_binary", "swift_library", "swift_macro")

swift_macro(
    name = "macroslib",
    srcs = ["macro.swift"],
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
    macros = [":macroslib"],
    module_name = "lib",
)

swift_binary(
    name = "main",
    srcs = ["main.swift"],
    deps = [":lib"],
)

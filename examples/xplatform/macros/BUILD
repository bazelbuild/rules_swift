load("//swift:swift.bzl", "swift_binary", "swift_library", "swift_test")
load(
    "//swift:swift_compiler_plugin.bzl",
    "swift_compiler_plugin",
    "swift_compiler_plugin_group",
    "universal_swift_compiler_plugin",
)

licenses(["notice"])

config_setting(
    name = "supports_macros",
    values = {"define": "supports_macros=1"},
)

swift_library(
    name = "stringify",
    srcs = ["Stringify.swift"],
    module_name = "Stringify",
    plugins = [":stringify_macro_group"],
)

swift_library(
    name = "stringify_universal",
    srcs = ["Stringify.swift"],
    module_name = "StringifyUniversal",
    plugins = [
        # We don't create and use a `stringify_macro_universal` here, but we
        # could have if we wanted to
        ":stringify_macro_universal",
        ":stringify2_macro_universal",
    ],
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

swift_compiler_plugin(
    name = "stringify2_macro",
    srcs = [
        "Stringify2Macro.swift",
        "Stringify2MacroPlugin.swift",
    ],
    module_name = "Stringify2MacroPlugin",
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

swift_compiler_plugin_group(
    name = "stringify_macro_group",
    plugins = [
        ":stringify_macro",
        ":stringify2_macro",
    ],
)

universal_swift_compiler_plugin(
    name = "stringify_macro_universal",
    plugin = ":stringify_macro",
)

universal_swift_compiler_plugin(
    name = "stringify2_macro_universal",
    plugin = ":stringify_macro",
)

swift_binary(
    name = "stringify_client",
    srcs = ["StringifyClient.swift"],
    deps = [":stringify"],
)

swift_binary(
    name = "stringify_universal_client",
    srcs = ["StringifyUniversalClient.swift"],
    deps = [":stringify_universal"],
)

swift_test(
    name = "stringify_macro_test",
    srcs = ["StringifyMacroTests.swift"],
    target_compatible_with = select({
        ":supports_macros": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [
        ":stringify_macro_group",
        # `stringify_macro` is in `stringify_macro_group`, but we list both to
        # show that it handles that fine
        ":stringify_macro",
        "@SwiftSyntax",
        "@SwiftSyntax//:SwiftSyntaxBuilder",
        "@SwiftSyntax//:SwiftSyntaxMacros",
    ],
)

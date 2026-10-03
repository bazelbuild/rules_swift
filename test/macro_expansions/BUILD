load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift_compiler_plugin.bzl", "swift_compiler_plugin")
load("//swift:swift_library.bzl", "swift_library")
load("//test:transitions.bzl", "transition_test")

licenses(["notice"])

# Share the version flag used to discover tests for the Xcode 26.4 CI job.
config_setting(
    name = "xcode_26_4_or_newer",
    flag_values = {"//test/hermetic_pcm:xcode_at_least_26_4": "True"},
)

swift_compiler_plugin(
    name = "nested_macros",
    srcs = ["NestedMacros.swift"],
    module_name = "NestedMacros",
    deps = [
        "@swift-syntax//:SwiftCompilerPlugin",
        "@swift-syntax//:SwiftSyntax",
        "@swift-syntax//:SwiftSyntaxBuilder",
        "@swift-syntax//:SwiftSyntaxMacros",
    ],
)

swift_library(
    name = "nested_macro_user",
    srcs = ["NestedMacroUser.swift"],
    plugins = [":nested_macros"],
)

filegroup(
    name = "macro_expansions",
    srcs = [":nested_macro_user"],
    output_group = "macro_expansions",
)

sh_test(
    name = "_macro_expansion_paths_test",
    srcs = ["macro_expansion_paths_test.sh"],
    args = ["$(rootpath :macro_expansions)"],
    data = [":macro_expansions"],
    tags = ["manual"],
)

# Macro expansion files are only emitted in debug builds.
transition_test(
    name = "macro_expansion_paths_test",
    args = ["test/macro_expansions/nested_macro_user.macro-expansions"],
    compilation_mode = "dbg",
    target = ":_macro_expansion_paths_test",
    target_compatible_with = select({
        ":xcode_26_4_or_newer": [],
        "@platforms//os:linux": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)
load(
    "//swift:swift_compiler_plugin.bzl",
    "swift_compiler_plugin",
)
load(
    "//swift:swift_compiler_plugin_import.bzl",
    "swift_compiler_plugin_import",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":rules.bzl", "reexport_swift_info")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_compiler_plugin(
    name = "plugin",
    srcs = ["Plugin.swift"],
    module_name = "MyPlugin",
    tags = FIXTURE_TAGS,
)

swift_compiler_plugin(
    name = "default_module_plugin",
    srcs = ["Plugin.swift"],
    tags = FIXTURE_TAGS,
)

swift_compiler_plugin(
    name = "empty_srcs_plugin",
    srcs = [],
    tags = FIXTURE_TAGS,
)

swift_compiler_plugin_import(
    name = "imported_plugin",
    executable = "fake_plugin.sh",
    module_names = [
        "ImportedPluginA",
        "ImportedPluginB",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "macro_library",
    srcs = ["Empty.swift"],
    plugins = [":plugin"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "imported_macro_library",
    srcs = ["Empty.swift"],
    plugins = [":imported_plugin"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "direct_consumer",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":macro_library"],
)

swift_library(
    name = "imported_direct_consumer",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":imported_macro_library"],
)

swift_library(
    name = "indirect_consumer",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":direct_consumer"],
)

reexport_swift_info(
    name = "reexported_macro_library",
    tags = FIXTURE_TAGS,
    deps = [":macro_library"],
)

swift_library(
    name = "reexported_consumer",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":reexported_macro_library"],
)

swift_binary(
    name = "binary_with_plugin",
    srcs = ["Empty.swift"],
    plugins = [":plugin"],
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "test_with_plugin",
    srcs = ["Empty.swift"],
    discover_tests = False,
    plugins = [":plugin"],
    tags = FIXTURE_TAGS,
)

swift_test(
    name = "plugin_unit_test",
    srcs = ["Empty.swift"],
    discover_tests = False,
    tags = FIXTURE_TAGS,
    deps = [":plugin"],
)

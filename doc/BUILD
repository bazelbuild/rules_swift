load("@bazel_gazelle//:def.bzl", "gazelle", "gazelle_binary")
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

_DOC_SRCS = {
    "api": (
        "//doc:api.bzl",
        [
            "//swift:module_name",
            "//swift:swift_common",
            "//swift:swift_interop_info",
            "//swift:swift_overlay_helpers",
        ],
    ),
    "providers": (
        "//swift:providers.bzl",
        ["//swift:providers"],
    ),
    "rules": (
        "//doc:rules.bzl",
        [
            "//mixed_language:mixed_language_library",
            "//proto:swift_proto_compiler",
            "//proto:swift_proto_library",
            "//proto:swift_proto_library_group",
            "//swift:swift_binary",
            "//swift:swift_compiler_plugin",
            "//swift:swift_compiler_plugin_import",
            "//swift:swift_cross_import_overlay",
            "//swift:swift_feature_allowlist",
            "//swift:swift_import",
            "//swift:swift_interop_hint",
            "//swift:swift_library",
            "//swift:swift_library_group",
            "//swift:swift_module_mapping",
            "//swift:swift_module_mapping_test",
            "//swift:swift_overlay",
            "//swift:swift_package_configuration",
            "//swift:swift_test",
        ],
    ),
}

write_file(
    name = "toc_template",
    out = "table_of_contents.vm",
    content = [
        "",
        "On this page:",
        "",
        "#foreach ($rule in $ruleInfos)",
        "  * [$rule.ruleName](#$rule.ruleName)",
        "#end",
        "#foreach ($providerInfo in $providerInfos)",
        "  * [$providerInfo.providerName](#$providerInfo.providerName)",
        "#end",
        "#foreach ($macroInfo in $macroInfos)",
        "  * [$macroInfo.macroName](#$macroInfo.macroName)",
        "#end",
        "#foreach ($functionInfo in $functionInfos)",
        "  * [$functionInfo.functionName](#$functionInfo.functionName)",
        "#end",
        "#foreach ($aspectInfo in $aspectInfos)",
        "  * [$aspectInfo.aspectName](#$aspectInfo.aspectName)",
        "#end",
        "#foreach ($repositoryRuleInfo in $repositoryRuleInfos)",
        "  * [$repositoryRuleInfo.ruleName](#$repositoryRuleInfo.ruleName)",
        "#end",
        "#foreach ($moduleExtensionInfo in $moduleExtensionInfos)",
        "  * [$moduleExtensionInfo.extensionName](#$moduleExtensionInfo.extensionName)",
        "#end",
    ],
)

write_file(
    name = "api_header",
    out = "api_header.vm",
    content = [
        "<!-- Generated with Stardoc, Do Not Edit! -->",
        "# Build API",
        "",
        "The `swift_common` module provides API access to the behavior",
        "implemented by the Swift build rules, so that other custom rules can",
        "invoke Swift compilation and/or linking as part of their",
        "implementation.",
        "",
        "Some API is exposed as free functions outside of the `swift_common`",
        "module.",
    ],
)

write_file(
    name = "rules_header",
    out = "rules_header.vm",
    content = [
        "<!-- Generated with Stardoc, Do Not Edit! -->",
        "",
        "${moduleDocstring}",
    ],
)

write_file(
    name = "providers_header",
    out = "providers_header.vm",
    content = [
        "<!-- Generated with Stardoc, Do Not Edit! -->",
        "",
        "The providers described below are propagated and required by various Swift",
        "build rules. Clients interested in writing custom rules that interface",
        "with the rules in this package should use these providers to communicate",
        "with the Swift build rules as needed.",
        "",
    ],
)

[
    stardoc(
        name = file + "_doc",
        out = file + ".md_",
        header_template = file + "_header.vm",
        input = input,
        table_of_contents_template = "table_of_contents.vm",
        deps = deps,
    )
    for file, (input, deps) in _DOC_SRCS.items()
]

# To make these tests pass, run
# bazel run //doc:update
[
    diff_test(
        name = "test_" + file,
        file1 = file + ".md_",
        file2 = file + ".md",
    )
    for file in _DOC_SRCS.keys()
]

write_file(
    name = "gen_update",
    out = "update.sh",
    content = [
        "#!/usr/bin/env bash",
        "cd $BUILD_WORKSPACE_DIRECTORY",
    ] + [
        "cp -fv bazel-bin/doc/{0}.md_ doc/{0}.md".format(
            file,
        )
        for file in _DOC_SRCS.keys()
    ],
)

sh_binary(
    name = "update",
    srcs = ["update.sh"],
    data = [file + ".md_" for file in _DOC_SRCS.keys()],
)

gazelle(
    name = "gazelle",
    gazelle = ":gazelle_bin",
    visibility = ["//visibility:private"],
)

gazelle_binary(
    name = "gazelle_bin",
    languages = [
        "@bazel_skylib_gazelle_plugin//bzl",
    ],
    visibility = ["//visibility:private"],
)

# Have to keep since bazel doesn't propagate a bzl_library for these files
# gazelle:ignore
bzl_library(
    name = "bazel_tools_bzl",
    srcs = ["@bazel_tools//tools:bzl_srcs"],
    visibility = ["//swift:__pkg__"],
)

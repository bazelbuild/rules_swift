"""Repository rule and utilities for generating Swift toolchain configurations.

This module provides the `toolchains_repository` repository rule and helper functions
for generating Bazel toolchain declarations. It creates platform-specific toolchain
configurations for Swift compilation, including embedded, exec, and cross-compilation
toolchains with appropriate platform constraints for macOS and Linux.
"""

_TOOLCHAIN_PLATFORM = """
# Toolchains from repository: `{toolchain_repository}`
## Embedded toolchains
toolchain(
    name = "cc_toolchain_embedded_{platform}",
    exec_compatible_with = {exec_compatible_with},
    target_compatible_with = [
        "@platforms//os:none",
    ],
    toolchain = "@{toolchain_repository}//:cc_toolchain_embedded",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "swift_toolchain_embedded_{platform}",
    exec_compatible_with = {exec_compatible_with},
    target_compatible_with = [
        "@platforms//os:none",
    ],
    toolchain = "@{toolchain_repository}//:swift_toolchain_embedded",
    toolchain_type = "@rules_swift//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

"""

_EXEC_TOOLCHAIN = """
## Exec toolchain
toolchain(
    name = "swift_toolchain_exec_{platform}",
    exec_compatible_with = {exec_compatible_with},
    target_compatible_with = {exec_compatible_with},
    toolchain = "@{toolchain_repository}//:swift_toolchain_exec",
    toolchain_type = "@rules_swift//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

"""

_XCODE_TOOLCHAINS = """
## Apple SDK toolchains
[
    toolchain(
        name = "xcode-sdk-toolchain-" + arch,
        exec_compatible_with = [
            "@platforms//os:macos",
        ],
        target_compatible_with = constraints,
        toolchain = "@{toolchain_repository}//:xcode-sdk-toolchain",
        toolchain_type = "@rules_swift//toolchains:sdk_toolchain_type",
        visibility = ["//visibility:public"],
    )
    for arch, constraints in APPLE_PLATFORMS_CONSTRAINTS.items()
]

[
    toolchain(
        name = "xcode-toolchain-" + arch,
        exec_compatible_with = [
            "@platforms//os:macos",
        ],
        target_compatible_with = constraints,
        toolchain = "@{toolchain_repository}//:xcode-toolchain",
        toolchain_type = "@rules_swift//toolchains:toolchain_type",
        visibility = ["//visibility:public"],
    )
    for arch, constraints in APPLE_PLATFORMS_CONSTRAINTS.items()
]

"""

def toolchains_for_platform(platform, toolchain_repository):
    # This assumption is baked into the API so we have to go along with it
    if platform == "xcode":
        exec_compatible_with = [
            "@platforms//os:macos",
        ]
    else:
        exec_compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format("aarch64" if "aarch64" in platform else "x86_64"),
        ]

    toolchains = _TOOLCHAIN_PLATFORM.format(
        exec_compatible_with = exec_compatible_with,
        platform = platform,
        toolchain_repository = toolchain_repository,
    )
    if platform == "xcode":
        toolchains += _XCODE_TOOLCHAINS.format(
            toolchain_repository = toolchain_repository,
        )
    else:
        toolchains += _EXEC_TOOLCHAIN.format(
            exec_compatible_with = exec_compatible_with,
            platform = platform,
            toolchain_repository = toolchain_repository,
        )
    return toolchains

def _toolchains_impl(repository_ctx):
    prelude = ""
    if repository_ctx.attr.include_apple_toolchains:
        prelude = """\
load(
    "@apple_support//configs:platforms.bzl",
    "APPLE_PLATFORMS_CONSTRAINTS",
)

"""
    repository_ctx.file(
        "BUILD.bazel",
        prelude + repository_ctx.attr.build_file_content,
    )

toolchains_repository = repository_rule(
    implementation = _toolchains_impl,
    attrs = {
        "build_file_content": attr.string(
            mandatory = True,
        ),
        "include_apple_toolchains": attr.bool(),
    },
)

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

## Exec toolchains
toolchain(
    name = "swift_toolchain_exec_{platform}",
    exec_compatible_with = {exec_compatible_with},
    target_compatible_with = {exec_compatible_with},
    toolchain = "@{toolchain_repository}//:swift_toolchain_exec",
    toolchain_type = "@rules_swift//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

"""

_SDK_TOOLCHAIN_PLATFORM = """
# Swift SDK toolchain from repository: `{sdk_repository}`
toolchain(
    name = "swift_toolchain_{target}_{platform}",
    exec_compatible_with = {exec_compatible_with},
    target_compatible_with = {target_compatible_with},
    toolchain = "@{sdk_repository}//:swift_toolchain_{target_suffix}",
    toolchain_type = "@rules_swift//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)
"""

_WASM_SDK_TOOLCHAIN_PLATFORM = """
# Swift SDK toolchains from repository: `{sdk_repository}`
toolchain(
    name = "swift_toolchain_{target}_{platform}",
    exec_compatible_with = {exec_compatible_with},
    target_compatible_with = {target_compatible_with},
    toolchain = "@{sdk_repository}//:swift_toolchain_{target_suffix}",
    toolchain_type = "@rules_swift//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

# The paired rules_cc toolchain drives the SDK bundle's own clang for the C
# side of the build (unlike Android, where the cc toolchain comes from the
# separately registered NDK). It only resolves for this wasm target platform,
# and because root-module registrations take precedence in toolchain
# resolution, a consumer who registers their own wasm cc toolchain wins over
# this one automatically.
toolchain(
    name = "cc_toolchain_{target}_{platform}",
    exec_compatible_with = {exec_compatible_with},
    target_compatible_with = {target_compatible_with},
    toolchain = "@{sdk_repository}//:cc_toolchain_{target_suffix}",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    visibility = ["//visibility:public"],
)
"""

def _exec_compatible_with_for_platform(platform):
    # This assumption is baked into the API so we have to go along with it
    if platform == "xcode":
        return [
            "@platforms//os:macos",
        ]
    return [
        "@platforms//os:linux",
        "@platforms//cpu:{}".format("aarch64" if "aarch64" in platform else "x86_64"),
    ]

def toolchains_for_platform(platform, toolchain_repository):
    return _TOOLCHAIN_PLATFORM.format(
        exec_compatible_with = _exec_compatible_with_for_platform(platform),
        platform = platform,
        toolchain_repository = toolchain_repository,
    )

def android_sdk_toolchains_for_platform(platform, sdk_repository, archs):
    """Returns Swift `toolchain` declarations for an Android Swift SDK.

    Args:
        platform: The platform name (e.g. "xcode" or "ubuntu22.04") whose
            standalone toolchain the SDK is paired with.
        sdk_repository: The name of the repository created by
            `swift_android_sdk_repository`.
        archs: The Android architectures (e.g. aarch64) to declare
            toolchains for.

    Returns:
        BUILD file content declaring the Swift toolchains.
    """
    content = ""
    for arch in archs:
        content += _SDK_TOOLCHAIN_PLATFORM.format(
            exec_compatible_with = _exec_compatible_with_for_platform(platform),
            platform = platform,
            sdk_repository = sdk_repository,
            target = "android_" + arch,
            target_compatible_with = [
                "@platforms//os:android",
                "@platforms//cpu:" + arch,
            ],
            target_suffix = arch,
        )
    return content

def wasm_sdk_toolchains_for_platform(platform, sdk_repository):
    """Returns `toolchain` declarations for a WebAssembly Swift SDK.

    Args:
        platform: The platform name (e.g. "xcode" or "ubuntu22.04") whose
            standalone toolchain the SDK is paired with.
        sdk_repository: The name of the repository created by
            `swift_wasm_sdk_repository`.

    Returns:
        BUILD file content declaring the Swift and C++ toolchains.
    """
    return _WASM_SDK_TOOLCHAIN_PLATFORM.format(
        exec_compatible_with = _exec_compatible_with_for_platform(platform),
        platform = platform,
        sdk_repository = sdk_repository,
        target = "wasm32",
        target_compatible_with = [
            "@platforms//os:wasi",
            "@platforms//cpu:wasm32",
        ],
        target_suffix = "wasm32",
    )

def _toolchains_impl(repository_ctx):
    repository_ctx.file("BUILD.bazel", repository_ctx.attr.build_file_content)
    if hasattr(repository_ctx, "repo_metadata"):
        return repository_ctx.repo_metadata(reproducible = True)
    return None

toolchains_repository = repository_rule(
    implementation = _toolchains_impl,
    attrs = {
        "build_file_content": attr.string(
            mandatory = True,
        ),
    },
)

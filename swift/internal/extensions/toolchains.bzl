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
# Swift SDK toolchains from repository: `{sdk_repository}`
toolchain(
    name = "swift_toolchain_{target}_{platform}",
    exec_compatible_with = {exec_compatible_with},
    target_compatible_with = {target_compatible_with},
    toolchain = "@{sdk_repository}//:swift_toolchain_{target_suffix}",
    toolchain_type = "@rules_swift//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

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

def wasm_sdk_toolchains_for_platform(platform, sdk_repository):
    """Returns `toolchain` declarations for a WebAssembly Swift SDK.

    Args:
        platform: The host platform name (e.g. "xcode" or "ubuntu22.04") whose
            standalone toolchain the SDK is paired with.
        sdk_repository: The name of the repository created by
            `swift_wasm_sdk_repository`.

    Returns:
        BUILD file content declaring the Swift and C++ toolchains.
    """
    return _SDK_TOOLCHAIN_PLATFORM.format(
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

def android_sdk_toolchains_for_platform(platform, sdk_repository, archs):
    """Returns `toolchain` declarations for an Android Swift SDK.

    Args:
        platform: The host platform name (e.g. "xcode" or "ubuntu22.04") whose
            standalone toolchain the SDK is paired with.
        sdk_repository: The name of the repository created by
            `swift_android_sdk_repository`.
        archs: The Android architectures ("aarch64", "x86_64") to declare
            toolchains for.

    Returns:
        BUILD file content declaring the Swift and C++ toolchains.
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

def static_linux_sdk_toolchains_for_platform(platform, sdk_repository, archs):
    """Returns `toolchain` declarations for a Static Linux Swift SDK.

    Args:
        platform: The host platform name (e.g. "xcode" or "ubuntu22.04") whose
            standalone toolchain the SDK is paired with.
        sdk_repository: The name of the repository created by
            `swift_static_linux_sdk_repository`.
        archs: The Static Linux architectures ("aarch64", "x86_64") to declare
            toolchains for.

    Returns:
        BUILD file content declaring the Swift and C++ toolchains.
    """
    content = ""
    for arch in archs:
        content += _SDK_TOOLCHAIN_PLATFORM.format(
            exec_compatible_with = _exec_compatible_with_for_platform(platform),
            platform = platform,
            sdk_repository = sdk_repository,
            target = "static_linux_" + arch,
            target_compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:" + arch,
                "@rules_swift//swift/toolchains:static_linux",
            ],
            target_suffix = "static_linux_" + arch,
        )
    return content

_NDK_HOST_OS_CONSTRAINT = {
    "darwin": "@platforms//os:macos",
    "linux": "@platforms//os:linux",
}

def android_libcxx_aliases(ndk_repos_by_host, archs):
    """Returns host-independent aliases for the NDK's `libc++_shared.so`.

    The NDK is fetched into a host-specific repository, but its
    `libc++_shared.so` (which an APK containing Swift code must bundle) is a
    target artifact whose content does not depend on the build host. These
    aliases let packaging rules reference it without naming the host, by
    selecting the NDK repository for the host the build runs on.

    Args:
        ndk_repos_by_host: A dict mapping NDK host OS ("darwin", "linux") to
            the name of the corresponding NDK repository.
        archs: The Android architectures ("aarch64", "x86_64").

    Returns:
        BUILD file content declaring one `libcxx_shared_<arch>` alias per arch.
    """
    hosts = sorted(ndk_repos_by_host.keys())
    default_repo = ndk_repos_by_host[hosts[0]]

    content = ""
    for arch in archs:
        branches = "".join([
            '        "{}": "@{}//:libcxx_shared_{}",\n'.format(
                _NDK_HOST_OS_CONSTRAINT[host],
                ndk_repos_by_host[host],
                arch,
            )
            for host in hosts
        ])
        content += """\
alias(
    name = "libcxx_shared_{arch}",
    actual = select({{
{branches}        "//conditions:default": "@{default_repo}//:libcxx_shared_{arch}",
    }}),
    visibility = ["//visibility:public"],
)

""".format(
            arch = arch,
            branches = branches,
            default_repo = default_repo,
        )
    return content

def _toolchains_impl(repository_ctx):
    repository_ctx.file("BUILD.bazel", repository_ctx.attr.build_file_content)

toolchains_repository = repository_rule(
    implementation = _toolchains_impl,
    attrs = {
        "build_file_content": attr.string(
            mandatory = True,
        ),
    },
)

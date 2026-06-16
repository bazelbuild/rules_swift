# Copyright 2022 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Definitions for bzlmod module extensions."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//swift/internal:repositories.bzl", "swift_rules_dependencies")
load("//swift/internal/extensions:standalone_toolchain.bzl", _standalone_toolchain = "standalone_toolchain")
load("//swift/internal/extensions:swift_releases.bzl", "SWIFT_RELEASES")
load(
    "//swift/internal/extensions:swift_sdk_releases.bzl",
    "ANDROID_NDK_RELEASES",
    "DEFAULT_ANDROID_NDK_VERSION",
    "SWIFT_SDK_RELEASES",
    "android_ndk_download_url",
    "static_linux_sdk_download_url",
    "swift_sdk_download_url",
)
load(
    "//swift/internal/extensions:swift_sdks.bzl",
    "ANDROID_ARCHS",
    "ANDROID_NDK_BUILD_FILE_CONTENT",
    "STATIC_LINUX_ARCHS",
    "swift_android_sdk_repository",
    "swift_static_linux_sdk_repository",
    "swift_wasm_sdk_repository",
)
load(
    "//swift/internal/extensions:toolchains.bzl",
    _android_libcxx_aliases = "android_libcxx_aliases",
    _android_sdk_toolchains_for_platform = "android_sdk_toolchains_for_platform",
    _static_linux_sdk_toolchains_for_platform = "static_linux_sdk_toolchains_for_platform",
    _toolchains_for_platform = "toolchains_for_platform",
    _toolchains_repository = "toolchains_repository",
    _wasm_sdk_toolchains_for_platform = "wasm_sdk_toolchains_for_platform",
)
load("//tools/explicit_modules:extensions.bzl", _system_sdk = "system_sdk")

system_sdk = _system_sdk

def _non_module_deps_impl(module_ctx):
    swift_rules_dependencies()

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True

    return module_ctx.extension_metadata(
        **metadata_kwargs
    )

non_module_deps = module_extension(implementation = _non_module_deps_impl)

def _ndk_host_os(platform):
    """Returns the Android NDK host OS for a host toolchain platform name."""
    return "darwin" if platform == "xcode" else "linux"

def _setup_wasm_sdk(*, tag, toolchain_name, swift_version, platforms):
    """Creates the repositories for a `swift.wasm_sdk` tag.

    Args:
        tag: The `wasm_sdk` tag.
        toolchain_name: The name of the `swift.toolchain` tag the SDK extends.
        swift_version: The Swift release version of that toolchain.
        platforms: The host platforms the toolchain was created for.

    Returns:
        BUILD file content with the `toolchain` declarations to add to the
        toolchains hub repository.
    """
    sha256 = tag.sha256
    if not sha256:
        if swift_version not in SWIFT_SDK_RELEASES or "wasm" not in SWIFT_SDK_RELEASES[swift_version]:
            fail("No known WebAssembly Swift SDK for version `{}`. Please choose one of {}, or provide the SDK's sha256.".format(
                swift_version,
                SWIFT_SDK_RELEASES.keys(),
            ))
        sha256 = SWIFT_SDK_RELEASES[swift_version]["wasm"]

    build_file_content = ""
    for platform in platforms:
        repository_name = "{}_wasm_sdk_{}".format(toolchain_name, platform)
        swift_wasm_sdk_repository(
            name = repository_name,
            sha256 = sha256,
            swift_version = swift_version,
            toolchain_repo = "{}_{}".format(toolchain_name, platform),
            url = swift_sdk_download_url(swift_version, "wasm"),
        )
        build_file_content += _wasm_sdk_toolchains_for_platform(
            platform = platform,
            sdk_repository = repository_name,
        )
    return build_file_content

def _setup_android_sdk(*, tag, toolchain_name, swift_version, platforms):
    """Creates the repositories for a `swift.android_sdk` tag.

    Args:
        tag: The `android_sdk` tag.
        toolchain_name: The name of the `swift.toolchain` tag the SDK extends.
        swift_version: The Swift release version of that toolchain.
        platforms: The host platforms the toolchain was created for.

    Returns:
        BUILD file content with the `toolchain` declarations to add to the
        toolchains hub repository.
    """
    sha256 = tag.sha256
    if not sha256:
        if swift_version not in SWIFT_SDK_RELEASES or "android" not in SWIFT_SDK_RELEASES[swift_version]:
            fail("No known Android Swift SDK for version `{}`. Please choose one of {}, or provide the SDK's sha256.".format(
                swift_version,
                SWIFT_SDK_RELEASES.keys(),
            ))
        sha256 = SWIFT_SDK_RELEASES[swift_version]["android"]

    ndk_version = tag.ndk_version or DEFAULT_ANDROID_NDK_VERSION
    ndk_sha256s = tag.ndk_sha256s
    if not ndk_sha256s:
        if ndk_version not in ANDROID_NDK_RELEASES:
            fail("No known Android NDK release `{}`. Please choose one of {}, or provide the NDK's sha256s.".format(
                ndk_version,
                ANDROID_NDK_RELEASES.keys(),
            ))
        ndk_sha256s = ANDROID_NDK_RELEASES[ndk_version]

    host_oses = {_ndk_host_os(platform): None for platform in platforms}
    ndk_repos_by_host = {}
    for host_os in host_oses:
        ndk_repo = "{}_android_ndk_{}".format(toolchain_name, host_os)
        ndk_repos_by_host[host_os] = ndk_repo
        http_archive(
            name = ndk_repo,
            build_file_content = ANDROID_NDK_BUILD_FILE_CONTENT,
            sha256 = ndk_sha256s.get(host_os, ""),
            strip_prefix = "android-ndk-" + ndk_version,
            url = android_ndk_download_url(ndk_version, host_os),
        )

    # Host-independent aliases for the NDK's `libc++_shared.so`, so an APK rule
    # can bundle it without naming the build host.
    build_file_content = _android_libcxx_aliases(
        ndk_repos_by_host = ndk_repos_by_host,
        archs = ANDROID_ARCHS,
    )
    for platform in platforms:
        ndk_repo = "{}_android_ndk_{}".format(toolchain_name, _ndk_host_os(platform))
        repository_name = "{}_android_sdk_{}".format(toolchain_name, platform)
        swift_android_sdk_repository(
            name = repository_name,
            api_level = tag.api_level,
            host_swiftc = "@{}_{}//:usr/bin/swiftc".format(toolchain_name, platform),
            ndk_repo = ndk_repo,
            ndk_source_properties = "@{}//:source.properties".format(ndk_repo),
            sha256 = sha256,
            swift_version = swift_version,
            toolchain_repo = "{}_{}".format(toolchain_name, platform),
            url = swift_sdk_download_url(swift_version, "android"),
        )
        build_file_content += _android_sdk_toolchains_for_platform(
            platform = platform,
            sdk_repository = repository_name,
            archs = ANDROID_ARCHS,
        )
    return build_file_content

def _setup_static_linux_sdk(*, tag, toolchain_name, swift_version, platforms):
    """Creates the repositories for a `swift.static_linux_sdk` tag.

    Args:
        tag: The `static_linux_sdk` tag.
        toolchain_name: The name of the `swift.toolchain` tag the SDK extends.
        swift_version: The Swift release version of that toolchain.
        platforms: The host platforms the toolchain was created for.

    Returns:
        BUILD file content with the `toolchain` declarations to add to the
        toolchains hub repository.
    """
    release = None
    if swift_version in SWIFT_SDK_RELEASES:
        release = SWIFT_SDK_RELEASES[swift_version].get("static_linux")

    sdk_version = tag.sdk_version
    if not sdk_version:
        if not release:
            fail("No known Static Linux Swift SDK version for Swift `{}`. Please provide sdk_version.".format(
                swift_version,
            ))
        sdk_version = release["version"]

    sha256 = tag.sha256
    if not sha256:
        if not release:
            fail("No known Static Linux Swift SDK for version `{}`. Please choose one of {}, or provide the SDK's sha256 and sdk_version.".format(
                swift_version,
                SWIFT_SDK_RELEASES.keys(),
            ))
        if sdk_version != release["version"]:
            fail("No known checksum for Static Linux Swift SDK version `{}` for Swift `{}`. Please provide sha256 when overriding sdk_version.".format(
                sdk_version,
                swift_version,
            ))
        sha256 = release["sha256"]

    build_file_content = ""
    for platform in platforms:
        repository_name = "{}_static_linux_sdk_{}".format(toolchain_name, platform)
        swift_static_linux_sdk_repository(
            name = repository_name,
            sha256 = sha256,
            swift_version = swift_version,
            toolchain_repo = "{}_{}".format(toolchain_name, platform),
            url = static_linux_sdk_download_url(swift_version, sdk_version),
        )
        build_file_content += _static_linux_sdk_toolchains_for_platform(
            platform = platform,
            sdk_repository = repository_name,
            archs = STATIC_LINUX_ARCHS,
        )
    return build_file_content

def _sdk_tags_by_toolchain_name(tags, kind):
    """Groups SDK tags by the toolchain they extend, rejecting duplicates."""
    tags_by_name = {}
    for tag in tags:
        if tag.toolchain_name in tags_by_name:
            fail("Only one `{}` tag may be used per toolchain, got multiple for `{}`.".format(
                kind,
                tag.toolchain_name,
            ))
        tags_by_name[tag.toolchain_name] = tag
    return tags_by_name

def _standalone_toolchain_impl(module_ctx):
    root_module = None
    for mod in module_ctx.modules:
        if not mod.is_root and not module_ctx.is_dev_dependency:
            fail("Only the root module can use the 'swift' extension. Packages meant to be used as deps should use dev_dependency = True")
        root_module = mod

    if not root_module:
        fail("Could not find a root module. This should never happen.")

    wasm_sdk_tags = _sdk_tags_by_toolchain_name(
        root_module.tags.wasm_sdk,
        "wasm_sdk",
    )
    android_sdk_tags = _sdk_tags_by_toolchain_name(
        root_module.tags.android_sdk,
        "android_sdk",
    )
    static_linux_sdk_tags = _sdk_tags_by_toolchain_name(
        root_module.tags.static_linux_sdk,
        "static_linux_sdk",
    )

    toolchain_names = [
        toolchain.name
        for toolchain in root_module.tags.toolchain
    ]
    for kind, tags in (
        ("wasm_sdk", wasm_sdk_tags),
        ("android_sdk", android_sdk_tags),
        ("static_linux_sdk", static_linux_sdk_tags),
    ):
        for toolchain_name in tags:
            if toolchain_name not in toolchain_names:
                fail("The `{}` tag references unknown toolchain `{}`. Please use the name of a `toolchain` tag: {}".format(
                    kind,
                    toolchain_name,
                    toolchain_names,
                ))

    toolchains_build_file_content = ""
    for toolchain in root_module.tags.toolchain:
        if toolchain.swift_version and toolchain.swift_version_file:
            fail("Cannot use both swift_version and swift_version_file together. Please choose one.")

        if not toolchain.swift_version and not toolchain.swift_version_file:
            fail("Neither `swift_version` nor `swift_version_file` are set. Please use one to select the version.")

        swift_version = toolchain.swift_version
        if toolchain.swift_version_file:
            swift_version = module_ctx.read(toolchain.swift_version_file).strip()

        if not toolchain.platform_sha256 and swift_version not in SWIFT_RELEASES:
            fail("Version `{}` is not supported by this version of rules_swift. Please choose one of: {}".format(
                swift_version,
                SWIFT_RELEASES.keys(),
            ))

        swift_releases = toolchain.platform_sha256.items() or SWIFT_RELEASES[swift_version].items()
        for platform, sha256 in swift_releases:
            repository_name = toolchain.name + "_{}".format(platform)
            _standalone_toolchain(
                name = repository_name,
                sha256 = sha256,
                platform = platform,
                swift_version = swift_version,
            )
            toolchains_build_file_content += _toolchains_for_platform(
                platform = platform,
                toolchain_repository = repository_name,
            )

        platforms = [platform for platform, _ in swift_releases]
        if toolchain.name in wasm_sdk_tags:
            toolchains_build_file_content += _setup_wasm_sdk(
                tag = wasm_sdk_tags[toolchain.name],
                toolchain_name = toolchain.name,
                swift_version = swift_version,
                platforms = platforms,
            )
        if toolchain.name in android_sdk_tags:
            toolchains_build_file_content += _setup_android_sdk(
                tag = android_sdk_tags[toolchain.name],
                toolchain_name = toolchain.name,
                swift_version = swift_version,
                platforms = platforms,
            )

        if toolchain.name in static_linux_sdk_tags:
            toolchains_build_file_content += _setup_static_linux_sdk(
                tag = static_linux_sdk_tags[toolchain.name],
                toolchain_name = toolchain.name,
                swift_version = swift_version,
                platforms = platforms,
            )

        _toolchains_repository(
            name = toolchain.name,
            build_file_content = toolchains_build_file_content,
        )

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True

    return module_ctx.extension_metadata(
        **metadata_kwargs
    )

_wasm_sdk = tag_class(
    attrs = {
        "sha256": attr.string(
            doc = """\
The expected SHA-256 of the SDK artifact bundle. May be omitted for Swift
versions known to this version of rules_swift.
""",
        ),
        "toolchain_name": attr.string(
            doc = "The name of the `toolchain` tag to add this Swift SDK to.",
            mandatory = True,
        ),
    },
    doc = """\
Downloads the WebAssembly Swift SDK matching a `toolchain` tag's Swift version
and defines Swift and C++ toolchains targeting `wasm32-unknown-wasip1`.

Register the generated toolchains for the host platforms you build on, e.g.:

```starlark
register_toolchains(
    "@swift_toolchain//:swift_toolchain_wasm32_xcode",
    "@swift_toolchain//:cc_toolchain_wasm32_xcode",
)
```

and build with a platform that has the `@platforms//os:wasi` and
`@platforms//cpu:wasm32` constraints.
""",
)

_android_sdk = tag_class(
    attrs = {
        "api_level": attr.int(
            default = 28,
            doc = "The Android API level to target.",
        ),
        "ndk_sha256s": attr.string_dict(
            doc = """\
A dictionary of NDK host OS ("darwin", "linux") to the expected SHA-256 of the
NDK archive. May be omitted for NDK versions known to this version of
rules_swift.
""",
        ),
        "ndk_version": attr.string(
            doc = """\
The Android NDK release (e.g. "r27c") whose sysroot and clang are used. The
Android Swift SDK requires r27 or later. Defaults to a version known to work
with the supported Swift releases.
""",
        ),
        "sha256": attr.string(
            doc = """\
The expected SHA-256 of the SDK artifact bundle. May be omitted for Swift
versions known to this version of rules_swift.
""",
        ),
        "toolchain_name": attr.string(
            doc = "The name of the `toolchain` tag to add this Swift SDK to.",
            mandatory = True,
        ),
    },
    doc = """\
Downloads the Android Swift SDK matching a `toolchain` tag's Swift version
(along with the Android NDK) and defines Swift and C++ toolchains targeting
`aarch64-unknown-linux-android` and `x86_64-unknown-linux-android`.

Register the generated toolchains for the host platforms you build on, e.g.:

```starlark
register_toolchains(
    "@swift_toolchain//:swift_toolchain_android_aarch64_xcode",
    "@swift_toolchain//:cc_toolchain_android_aarch64_xcode",
)
```

and build with a platform that has the `@platforms//os:android` and
`@platforms//cpu:aarch64` (or `x86_64`) constraints.
""",
)

_static_linux_sdk = tag_class(
    attrs = {
        "sdk_version": attr.string(
            doc = """\
The Static Linux SDK version in the artifact bundle filename. May be omitted
for Swift/SDK version pairs known to this version of rules_swift. If this
overrides the known SDK version, `sha256` must also be provided.
""",
        ),
        "sha256": attr.string(
            doc = """\
The expected SHA-256 of the SDK artifact bundle. May be omitted only for
Swift/SDK version pairs known to this version of rules_swift.
""",
        ),
        "toolchain_name": attr.string(
            doc = "The name of the `toolchain` tag to add this Swift SDK to.",
            mandatory = True,
        ),
    },
    doc = """\
Downloads the Static Linux Swift SDK matching a `toolchain` tag's Swift version
and defines Swift and C++ toolchains targeting `x86_64-swift-linux-musl` and
`aarch64-swift-linux-musl`.

Register the generated toolchains for the host platforms you build on, e.g.:

```starlark
register_toolchains(
    "@swift_toolchain//:swift_toolchain_static_linux_x86_64_xcode",
    "@swift_toolchain//:cc_toolchain_static_linux_x86_64_xcode",
)
```

and build with a platform that has `@platforms//os:linux`,
`@platforms//cpu:x86_64` (or `aarch64`), and
`@rules_swift//swift/toolchains:static_linux` constraints.

On Linux hosts, register the Static Linux SDK toolchains before generic
same-architecture Linux Swift toolchains, since both can match a Static Linux
platform and Bazel chooses by registration order.
""",
)

_toolchain = tag_class(attrs = {
    "name": attr.string(
        doc = "Repository name of the generated toolchain",
        mandatory = True,
    ),
    "platform_sha256": attr.string_dict(
        doc = """A string dictionary of platforms and the corresponding SHA256 of their toolchain archive.

Use the `swift-releases` utility to download swift archives for a given version and calculate
their hashes. For instance:
`bazel run @rules_swift//tools/swift-releases -- list 6.2.4`
""",
    ),
    "swift_version": attr.string(doc = "Version of the swift toolchain to be installed. Cannot be used concurrently with `swift_version_file`"),
    "swift_version_file": attr.label(doc = "A label to the .swift_version file to use. Cannot be used concurrently with `swift_version`"),
})

swift = module_extension(
    implementation = _standalone_toolchain_impl,
    tag_classes = {
        "android_sdk": _android_sdk,
        "static_linux_sdk": _static_linux_sdk,
        "toolchain": _toolchain,
        "wasm_sdk": _wasm_sdk,
    },
)

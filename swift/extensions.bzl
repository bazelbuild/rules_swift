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
load("//swift/internal/extensions:standalone_toolchain.bzl", "standalone_toolchain")
load("//swift/internal/extensions:swift_releases.bzl", "SWIFT_RELEASES")
load(
    "//swift/internal/extensions:swift_sdk_releases.bzl",
    "SWIFT_SDK_RELEASES",
    "swift_sdk_download_url",
)
load(
    "//swift/internal/extensions:swift_sdks.bzl",
    "ANDROID_ARCHS",
    "swift_android_sdk_repository",
    "swift_wasm_sdk_repository",
)
load(
    "//swift/internal/extensions:toolchains.bzl",
    "android_sdk_toolchains_for_platform",
    "toolchains_for_platform",
    "toolchains_repository",
    "wasm_sdk_toolchains_for_platform",
)
load("//tools/explicit_modules:extensions.bzl", _system_sdk = "system_sdk")

system_sdk = _system_sdk

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
        if swift_version not in SWIFT_SDK_RELEASES:
            fail("No known Android Swift SDK for version `{}`. Please choose one of {}, or provide the SDK's sha256.".format(
                swift_version,
                SWIFT_SDK_RELEASES.keys(),
            ))
        sha256 = SWIFT_SDK_RELEASES[swift_version]["android"]

    build_file_content = ""
    for platform in platforms:
        repository_name = "{}_android_sdk_{}".format(toolchain_name, platform)
        swift_android_sdk_repository(
            name = repository_name,
            paired_swiftc = "@{}_{}//:usr/bin/swiftc".format(toolchain_name, platform),
            sha256 = sha256,
            swift_version = swift_version,
            toolchain_repo = "{}_{}".format(toolchain_name, platform),
            url = swift_sdk_download_url(swift_version, "android"),
        )
        build_file_content += android_sdk_toolchains_for_platform(
            platform = platform,
            sdk_repository = repository_name,
            archs = ANDROID_ARCHS,
        )
    return build_file_content

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
        if swift_version not in SWIFT_SDK_RELEASES:
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
        build_file_content += wasm_sdk_toolchains_for_platform(
            platform = platform,
            sdk_repository = repository_name,
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

    android_sdk_tags = _sdk_tags_by_toolchain_name(
        root_module.tags.android_sdk,
        "android_sdk",
    )
    wasm_sdk_tags = _sdk_tags_by_toolchain_name(
        root_module.tags.wasm_sdk,
        "wasm_sdk",
    )

    toolchain_names = [
        toolchain.name
        for toolchain in root_module.tags.toolchain
    ]
    for toolchain_name in android_sdk_tags:
        if toolchain_name not in toolchain_names:
            fail("The `android_sdk` tag references unknown toolchain `{}`. Please use the name of a `toolchain` tag: {}".format(
                toolchain_name,
                toolchain_names,
            ))
    for toolchain_name in wasm_sdk_tags:
        if toolchain_name not in toolchain_names:
            fail("The `wasm_sdk` tag references unknown toolchain `{}`. Please use the name of a `toolchain` tag: {}".format(
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
            standalone_toolchain(
                name = repository_name,
                sha256 = sha256,
                platform = platform,
                swift_version = swift_version,
            )
            toolchains_build_file_content += toolchains_for_platform(
                platform = platform,
                toolchain_repository = repository_name,
            )

        platforms = [platform for platform, _ in swift_releases]
        if toolchain.name in android_sdk_tags:
            toolchains_build_file_content += _setup_android_sdk(
                tag = android_sdk_tags[toolchain.name],
                toolchain_name = toolchain.name,
                swift_version = swift_version,
                platforms = platforms,
            )
        if toolchain.name in wasm_sdk_tags:
            toolchains_build_file_content += _setup_wasm_sdk(
                tag = wasm_sdk_tags[toolchain.name],
                toolchain_name = toolchain.name,
                swift_version = swift_version,
                platforms = platforms,
            )

        toolchains_repository(
            name = toolchain.name,
            build_file_content = toolchains_build_file_content,
        )

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True

    return module_ctx.extension_metadata(
        **metadata_kwargs
    )

_android_sdk = tag_class(
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
Downloads the Android Swift SDK matching a `toolchain` tag's Swift version and
defines Swift toolchains targeting Android.
""",
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
        "toolchain": _toolchain,
        "wasm_sdk": _wasm_sdk,
    },
)

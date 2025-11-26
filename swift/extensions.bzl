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
load("//swift/internal:extensions/standalone_toolchain.bzl", _standalone_toolchain = "standalone_toolchain")
load(
    "//swift/internal:extensions/toolchains.bzl",
    _toolchains_for_platform = "toolchains_for_platform",
    _toolchains_repository = "toolchains_repository",
)
load("//swift/internal:repositories.bzl", "swift_rules_dependencies")

def _non_module_deps_impl(module_ctx):
    swift_rules_dependencies()

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True

    return module_ctx.extension_metadata(
        **metadata_kwargs
    )

non_module_deps = module_extension(implementation = _non_module_deps_impl)

# This mapping is intended to map each version to its supported platforms and checksums
_SWIFT_RELEASES = {
    "6.2.1": {
        "xcode": "4ca13d0abd364664d19facd75e23630c0884898bbcaf1920b45df288bdb86cb2",
        "amazonlinux2": "218fc55ba7224626fd25f8ca285b083fda020e3737146e2fe10b8ae9aaf2ae97",
        "amazonlinux2-aarch64": "00999039a82a81b1e9f3915eb2c78b63552fe727bcbfe9a2611628ac350287f2",
        "debian12": "d6405e4fb7f092cbb9973a892ce8410837b4335f67d95bf8607baef1f69939e4",
        "debian12-aarch64": "522d231bb332fe5da9648ca7811e8054721f05eccd1eefae491cf4a86eab4155",
        "fedora39": "ec78360dfa7817d7637f207b1ffb3a22164deb946c9a9f8c40ab8871856668e8",
        "fedora39-aarch64": "d8bc04e7e283e314d1b96adc55e1803dd01a0106dc0d0263e784a5c9f2a46d3b",
        "ubi9": "9a082c3efdeda2e65cbc7038d0c295b75fa48f360369b2538449fc665192da3e",
        "ubi9-aarch64": "47f109f1f63fa24df3659676bb1afac2fdd05c0954d4f00977da6a868dd31e66",
        "ubuntu22.04": "5ec23d4004f760fafdbb76c21e380d3bacef1824300427a458dc88c1c0bef381",
        "ubuntu22.04-aarch64": "ab5f3eb0349c575c38b96ed10e9a7ffa2741b0038285c12d56251a38749cadf0",
        "ubuntu24.04": "4022cb64faf7e2681c19f9b62a22fb7d9055db6194d9e4a4bef9107b6ce10946",
        "ubuntu24.04-aarch64": "3b70a3b23b9435c37112d96ee29aa70061e23059ef9c4d3cfa4951f49c4dfedb",
    },
}

def _standalone_toolchain_impl(module_ctx):
    root_module = None
    for mod in module_ctx.modules:
        if not mod.is_root:
            fail("Only the root module can use the 'swift' extension")
        root_module = mod

    if not root_module:
        fail("Could not find a root module. This should never happen.")

    toolchains_build_file_content = ""
    for toolchain in root_module.tags.toolchain:
        if toolchain.swift_version and toolchain.swift_version_file:
            fail("Cannot use both swift_version and swift_version_file together. Please choose one.")

        if not toolchain.swift_version and not toolchain.swift_version_file:
            fail("Neither `swift_version` nor `swift_version_file` are set. Please use one to select the version.")

        swift_version = toolchain.swift_version
        if toolchain.swift_version_file:
            swift_version = module_ctx.read(toolchain.swift_version_file).strip()

        if swift_version not in _SWIFT_RELEASES:
            fail("Version `{}` is not supported by this version of rules_swift. Please choose one of: {}".format(
                swift_version,
                _SWIFT_RELEASES.keys(),
            ))

        for platform, sha256 in _SWIFT_RELEASES[swift_version].items():
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
        _toolchains_repository(
            name = toolchain.name,
            build_file_content = toolchains_build_file_content,
        )

_toolchain = tag_class(attrs = {
    "name": attr.string(
        doc = "Repository name of the generated toolchain",
        mandatory = True,
    ),
    "swift_version": attr.string(doc = "Version of the swift toolchain to be installed. Cannot be used concurrently with `swift_version_file`"),
    "swift_version_file": attr.label(doc = "A label to the .swift_version file to use. Cannot be used concurrently with `swift_version`"),
})

swift = module_extension(
    implementation = _standalone_toolchain_impl,
    tag_classes = {
        "toolchain": _toolchain,
    },
)

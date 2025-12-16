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
load("//swift/internal:extensions/swift_releases.bzl", "SWIFT_RELEASES")
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

        if swift_version not in SWIFT_RELEASES:
            fail("Version `{}` is not supported by this version of rules_swift. Please choose one of: {}".format(
                swift_version,
                SWIFT_RELEASES.keys(),
            ))

        for platform, sha256 in SWIFT_RELEASES[swift_version].items():
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

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True

    return module_ctx.extension_metadata(
        **metadata_kwargs
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

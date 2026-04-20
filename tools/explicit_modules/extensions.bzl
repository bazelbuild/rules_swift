# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""Configure explicit module repos for all Xcode verisons."""

load("@bazel_tools//tools/osx:xcode_configure.bzl", "run_xcode_locator")
load(
    ":precomputed_xcode_explicit_module_repo.bzl",
    "precomputed_xcode_explicit_module_repo",
)
load(":xcode_explicit_module_hub_repo.bzl", "xcode_explicit_module_hub_repo")
load(":xcode_explicit_module_repo.bzl", "xcode_explicit_module_repo")
load(":xcode_locator_repo.bzl", "xcode_locator_repo")

_XCODE_LOCATOR_SRC = Label("@bazel_tools//tools/osx:xcode_locator.m")
_LOCATOR_REPO = "apple_sdk_xcode_locator"
_LOCATOR_LABEL = "@{}//:xcode-locator-bin".format(_LOCATOR_REPO)

def _sanitize(v):
    return v.replace(".", "_").replace("-", "_")

def _default_xcode_path(module_ctx):
    result = module_ctx.execute(
        ["xcode-select", "-p"],
        environment = {"DEVELOPER_DIR": module_ctx.os.environ.get("DEVELOPER_DIR", "")},
    )
    output = result.stdout.strip()
    if result.return_code != 0 or not output:
        fail("xcode-select failed.\nstdout:\n{}\nstderr:\n{}".format(
            output,
            result.stderr,
        ))

    # TODO: Should this be supported?
    if output == "/Library/Developer/CommandLineTools":
        return None
    return output

def _generate_pinned_repos(configs):
    seen = {}
    versions_ordered = []
    default_manifest = None
    for tag in configs:
        if tag.xcode_version in seen:
            fail(
                "Duplicate sdk.config() for xcode_version '{}'.".format(
                    tag.xcode_version,
                ),
            )
        seen[tag.xcode_version] = True
        repo_name = "apple_sdk_xcode_" + _sanitize(tag.xcode_version)
        precomputed_xcode_explicit_module_repo(
            name = repo_name,
            xcode_version = tag.xcode_version,
            build_file = tag.build_file,
        )
        versions_ordered.append(tag.xcode_version)
        if default_manifest == None:
            default_manifest = "@{}//:module_names.json".format(repo_name)

    xcode_explicit_module_hub_repo(
        name = "apple_sdk",
        xcode_versions = versions_ordered,
        default_manifest = default_manifest,
    )

def _generate_local_repos(module_ctx):
    toolchains, err = run_xcode_locator(module_ctx, _XCODE_LOCATOR_SRC)
    if err:
        fail("xcode-locator failed: " + err)
    if not toolchains:
        fail("No Xcodes found on this host.")

    default_path = _default_xcode_path(module_ctx)
    if not default_path:
        default_path = sorted(
            toolchains,
            key = lambda t: t.version,
            reverse = True,
        )[0].developer_dir

    xcode_locator_repo(name = _LOCATOR_REPO)

    versions_ordered = []
    default_manifest = None
    for tc in toolchains:
        repo_name = "apple_sdk_xcode_" + _sanitize(tc.version)
        xcode_explicit_module_repo(
            name = repo_name,
            xcode_version = tc.version,
            xcode_locator = _LOCATOR_LABEL,
        )
        versions_ordered.append(tc.version)
        if tc.developer_dir == default_path:
            default_manifest = "@{}//:module_names.json".format(repo_name)

    xcode_explicit_module_hub_repo(
        name = "apple_sdk",
        xcode_versions = versions_ordered,
        default_manifest = default_manifest,
    )

def _sdk_extension_impl(module_ctx):
    configs = []
    for mod in module_ctx.modules:
        for tag in mod.tags.config:
            configs.append(tag)

    if configs:
        _generate_pinned_repos(configs)
    else:
        _generate_local_repos(module_ctx)

_config_tag = tag_class(
    attrs = {
        "xcode_version": attr.string(
            mandatory = True,
            doc = "Canonical Xcode version string (e.g. 26.4.0.17E192).",
        ),
        "build_file": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Explicit module BUILD for the given Xcode.",
        ),
    },
    doc = "Manually pass the explicit module BUILD file for a specific Xcode version",
)

apple_sdk = module_extension(
    implementation = _sdk_extension_impl,
    tag_classes = {"config": _config_tag},
    doc = "Configure BUILD files for explicit modules for all installed Xcode versions.",
    environ = [
        "DEVELOPER_DIR",
        "XCODE_VERSION",
    ],
)

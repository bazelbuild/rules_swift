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
_LOCATOR_REPO = "system_sdk_xcode_locator"
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
        if tag.version in seen:
            fail(
                "Duplicate system_sdk.configure_xcode() for Xcode version '{}'.".format(
                    tag.version,
                ),
            )
        seen[tag.version] = True
        repo_name = "system_sdk_xcode_" + _sanitize(tag.version)
        precomputed_xcode_explicit_module_repo(
            name = repo_name,
            xcode_version = tag.version,
            build_file = tag.build_file,
        )
        versions_ordered.append(tag.version)
        if default_manifest == None:
            default_manifest = "@{}//:module_names.json".format(repo_name)

    xcode_explicit_module_hub_repo(
        name = "system_sdk",
        xcode_versions = versions_ordered,
        default_manifest = default_manifest,
    )

def _generate_local_repos(module_ctx, sdks):
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
        repo_name = "system_sdk_xcode_" + _sanitize(tc.version)
        xcode_explicit_module_repo(
            name = repo_name,
            sdks = sdks,
            xcode_version = tc.version,
            xcode_locator = _LOCATOR_LABEL,
        )
        versions_ordered.append(tc.version)
        if tc.developer_dir == default_path:
            default_manifest = "@{}//:module_names.json".format(repo_name)

    xcode_explicit_module_hub_repo(
        name = "system_sdk",
        xcode_versions = versions_ordered,
        default_manifest = default_manifest,
    )

def _collect_sdks(module_ctx):
    # Default to scanning the most common SDKs to save time.
    names = {"MacOSX": True, "iPhoneOS": True, "iPhoneSimulator": True}
    for mod in module_ctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.configure_sdks:
            if tag.include_all:
                return {}  # If we pass nothing to scan.py it will include everything
            for name in tag.names:
                names[name] = True
    return sorted(names.keys())

def _sdk_extension_impl(module_ctx):
    configs = []
    for mod in module_ctx.modules:
        for tag in mod.tags.configure_xcode:
            configs.append(tag)

    if configs:
        _generate_pinned_repos(configs)
    elif module_ctx.os.name != "mac os x":
        _system_sdk_stub_repo(name = "system_sdk")
    else:
        _generate_local_repos(module_ctx, _collect_sdks(module_ctx))

_STUB_BUILD_FILE = """\
load(
    "@build_bazel_rules_swift//swift:swift.bzl",
    "system_module_group",
)

package(default_visibility = ["//visibility:public"])

system_module_group(name = "all_modules")
"""

def _system_sdk_stub_repo_impl(rctx):
    rctx.file("BUILD.bazel", _STUB_BUILD_FILE)

_system_sdk_stub_repo = repository_rule(
    implementation = _system_sdk_stub_repo_impl,
    doc = "Empty hub repo used on non-macOS hosts so `@system_sdk//:all_modules` always resolves.",
)

_configure_xcode_tag = tag_class(
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

_configure_sdks_tag = tag_class(
    attrs = {
        "names": attr.string_list(
            default = [],
            doc = "SDK names to scan (e.g. 'MacOSX', 'iPhoneOS')",
        ),
        "include_all": attr.bool(
            default = False,
            doc = "Whether to include all SDKs instead of just the ones specified in 'names'.",
        ),
    },
    doc = "Limit dynamic scanning to a specific subset of Apple SDKs.",
)

system_sdk = module_extension(
    implementation = _sdk_extension_impl,
    tag_classes = {
        "configure_xcode": _configure_xcode_tag,
        "configure_sdks": _configure_sdks_tag,
    },
    doc = "Generate BUILD files for explicit modules.",
    environ = [
        "DEVELOPER_DIR",
        "XCODE_VERSION",
    ],
)

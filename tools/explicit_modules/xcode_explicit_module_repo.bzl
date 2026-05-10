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

"""Per-Xcode explicit module BUILD file config generator."""

def _resolve_developer_dir(rctx):
    locator = rctx.path(rctx.attr.xcode_locator)
    result = rctx.execute([str(locator), rctx.attr.xcode_version], timeout = 30)
    output = result.stdout.strip()
    if result.return_code != 0:
        fail(
            "xcode-locator failed.\nversion:{}\nstdout:\n{}\nstderr:\n{}".format(
                rctx.attr.xcode_version,
                output,
                result.stderr,
            ),
        )
    return output

def _exclude_module_args(exclude_modules):
    args = []
    for sdk, modules in sorted(exclude_modules.items()):
        for module in sorted(modules):
            args.extend(["--exclude-module", "{}:{}".format(sdk, module)])
    return args

def _xcode_explicit_module_repo_impl(rctx):
    developer_dir = _resolve_developer_dir(rctx)
    rctx.report_progress("Scanning SDKs for Xcode {}".format(rctx.attr.xcode_version))
    rctx.watch(rctx.attr._script)
    result = rctx.execute(
        [
            "/usr/bin/python3",
            rctx.attr._script,
            "--output",
            "BUILD.bazel",
            "--module-names",
            "module_names.json",
        ] + _exclude_module_args(rctx.attr.exclude_modules) + list(rctx.attr.sdks),
        environment = {"DEVELOPER_DIR": developer_dir},
    )
    if result.return_code != 0:
        fail(
            "error: scanning failed for Xcode {}:\nstdout:\n{}\nstderr:\n{}".format(
                rctx.attr.xcode_version,
                result.stdout,
                result.stderr,
            ),
        )

xcode_explicit_module_repo = repository_rule(
    implementation = _xcode_explicit_module_repo_impl,
    attrs = {
        "exclude_modules": attr.string_list_dict(
            default = {},
            doc = "Dictionary of SDK names to module names that should be excluded from scanning.",
        ),
        "sdks": attr.string_list(
            doc = "Optional list of SDK names (e.g. 'MacOSX', 'iPhoneSimulator') to scan. If empty, all SDKs are scanned.",
        ),
        "xcode_version": attr.string(
            mandatory = True,
            doc = "Canonical Xcode version string (e.g. 26.4.0.17E192).",
        ),
        "xcode_locator": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Label of the compiled xcode-locator binary.",
        ),
        "_script": attr.label(
            default = Label("//tools/explicit_modules:scan.py"),
            allow_single_file = True,
        ),
    },
    doc = "Discover all explicit module targets for all SDKs in a given Xcode version.",
    configure = True,
    environ = [
        "DEVELOPER_DIR",
        "XCODE_VERSION",
    ],
)

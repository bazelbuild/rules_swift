# Copyright 2018 The Bazel Authors. All rights reserved.
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

"""Implementation of the `swift_import` rule."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(":attrs.bzl", "swift_common_rule_attrs")
load(":compiling.bzl", "new_objc_provider")
load(":deps.bzl", "legacy_build_swift_info")
load(":providers.bzl", "SwiftClangModuleInfo", "merge_swift_clang_module_infos")

def _swift_import_impl(ctx):
    archives = ctx.files.archives
    deps = ctx.attr.deps
    swiftdocs = ctx.files.swiftdocs
    swiftmodules = ctx.files.swiftmodules

    providers = [
        DefaultInfo(
            files = depset(direct = archives + swiftdocs + swiftmodules),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        legacy_build_swift_info(
            deps = deps,
            direct_libraries = archives,
            direct_swiftdocs = swiftdocs,
            direct_swiftmodules = swiftmodules,
        ),
        # Propagate an `Objc` provider so that Apple-specific rules like `apple_binary` will link
        # the imported library properly. Typically we'd want to only propagate this if the
        # toolchain reports that it supports Objective-C interop, but that creates a problematic
        # cyclic dependency for built-from-source toolchains, so we propagate it unconditionally;
        # it will be ignored on non-Apple platforms anyway.
        new_objc_provider(
            deps = deps,
            include_path = None,
            link_inputs = [],
            linkopts = [],
            module_map = None,
            objc_header = None,
            static_archives = archives,
            swiftmodules = swiftmodules,
        ),
    ]

    # Only propagate `SwiftClangModuleInfo` if any of our deps does.
    if any([SwiftClangModuleInfo in dep for dep in deps]):
        clang_module = merge_swift_clang_module_infos(deps)
        providers.append(clang_module)

    return providers

swift_import = rule(
    attrs = dicts.add(
        swift_common_rule_attrs(),
        {
            "archives": attr.label_list(
                allow_empty = False,
                allow_files = ["a"],
                doc = """
The list of `.a` files provided to Swift targets that depend on this target.
""",
                mandatory = True,
            ),
            "swiftdocs": attr.label_list(
                allow_empty = True,
                allow_files = ["swiftdoc"],
                doc = """
The list of `.swiftdoc` files provided to Swift targets that depend on this target.
""",
                default = [],
                mandatory = False,
            ),
            "swiftmodules": attr.label_list(
                allow_empty = False,
                allow_files = ["swiftmodule"],
                doc = """
The list of `.swiftmodule` files provided to Swift targets that depend on this target.
""",
                mandatory = True,
            ),
        },
    ),
    doc = """
Allows for the use of precompiled Swift modules as dependencies in other `swift_library` and
`swift_binary` targets.
""",
    implementation = _swift_import_impl,
)

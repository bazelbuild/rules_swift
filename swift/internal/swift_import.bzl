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

load(":api.bzl", "swift_common")
load(":attrs.bzl", "swift_common_rule_attrs")
load(":compiling.bzl", "new_objc_provider")
load(":providers.bzl", "SwiftClangModuleInfo", "SwiftToolchainInfo", "merge_swift_clang_module_infos")
load("@bazel_skylib//lib:dicts.bzl", "dicts")

def _link_name(library):
    return library[3:-2]

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
        swift_common.build_swift_info(
            deps = deps,
            direct_libraries = archives,
            direct_swiftdocs = swiftdocs,
            direct_swiftmodules = swiftmodules,
        ),
    ]

    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    objc_fragment = (ctx.fragments.objc if toolchain.supports_objc_interop else None)
    if toolchain.supports_objc_interop and objc_fragment:
        for index, archive in enumerate(archives):
            library_path = "-L{}".format(archive.dirname)
            library_link_command = "-l{}".format(_link_name(archive.basename))
            linkopts = [library_path, library_link_command] + swift_common.swift_runtime_linkopts(False, toolchain)

            providers.append(new_objc_provider(
                deps = deps + toolchain.implicit_deps,
                include_path = archive.dirname,
                link_inputs = [archive],
                linkopts = linkopts,
                module_map = None,
                objc_header = None,
                static_archive = archive,
                swiftmodule = swiftmodules[index],
            ))

    # Only propagate `SwiftClangModuleInfo` if any of our deps does.
    if any([SwiftClangModuleInfo in dep for dep in deps]):
        clang_module = merge_swift_clang_module_infos(deps)
        providers.append(clang_module)

    return providers

swift_import = rule(
    attrs = dicts.add(
        swift_common_rule_attrs(),
        swift_common.toolchain_attrs(),
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
    fragments = ["objc"],
    implementation = _swift_import_impl,
)

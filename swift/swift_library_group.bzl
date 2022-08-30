# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Implementation of the `swift_library_group` rule."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//swift/internal:attrs.bzl", "swift_deps_attr", "swift_toolchain_attrs")
load("//swift/internal:toolchain_utils.bzl", "use_swift_toolchain")
load("//swift/internal:utils.bzl", "get_providers")
load(":providers.bzl", "SwiftInfo")
load(":swift_clang_module_aspect.bzl", "swift_clang_module_aspect")
load(":swift_common.bzl", "swift_common")

def _swift_library_group_impl(ctx):
    deps = ctx.attr.deps
    deps_cc_infos = [
        dep[CcInfo]
        for dep in deps
        if CcInfo in dep
    ]
    swift_toolchain = swift_common.get_toolchain(ctx)

    return [
        DefaultInfo(),
        CcInfo(
            compilation_context = cc_common.merge_cc_infos(
                cc_infos = deps_cc_infos,
            ).compilation_context,
            linking_context = cc_common.merge_linking_contexts(
                linking_contexts = [
                    cc_info.linking_context
                    for cc_info in (
                        deps_cc_infos +
                        swift_toolchain.implicit_deps_providers.cc_infos
                    )
                ] + [
                    cc_common.create_linking_context(
                        linker_inputs = depset(
                            direct = [
                                cc_common.create_linker_input(
                                    owner = ctx.label,
                                ),
                            ],
                        ),
                    ),
                ],
            ),
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
        ),
        swift_common.create_swift_info(
            swift_infos = get_providers(deps, SwiftInfo),
        ),
        # Propagate an `apple_common.Objc` provider with linking info about the
        # library so that linking with Apple Starlark APIs/rules works
        # correctly.
        # TODO(b/171413861): This can be removed when the Obj-C rules are
        # migrated to use `CcLinkingContext`.
        apple_common.new_objc_provider(
            providers = get_providers(
                deps,
                apple_common.Objc,
            ) + swift_toolchain.implicit_deps_providers.objc_infos,
        ),
    ]

swift_library_group = rule(
    attrs = dicts.add(
        swift_toolchain_attrs(),
        {
            "deps": swift_deps_attr(
                aspects = [swift_clang_module_aspect],
                doc = """\
A list of targets that should be included in the group.
""",
            ),
        },
    ),
    doc = """\
Groups Swift compatible libraries (e.g. `swift_library` and `objc_library`).
The target can be used anywhere a `swift_library` can be used. It behaves
similar to source-less `{cc,obj}_library` targets.

Unlike `swift_module_alias`, a new module isn't created for this target, you
need to import the grouped libraries directly.
""",
    implementation = _swift_library_group_impl,
    toolchains = use_swift_toolchain(),
)

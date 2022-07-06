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

"""Implementation of the `swift_module_alias` rule."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(":compiling.bzl", "new_objc_provider", "output_groups_from_other_compilation_outputs")
load(":derived_files.bzl", "derived_files")
load(":providers.bzl", "SwiftInfo", "SwiftToolchainInfo")
load(":swift_common.bzl", "swift_common")
load(":utils.bzl", "compact", "get_providers")

def _swift_module_alias_impl(ctx):
    deps = ctx.attr.deps
    module_mapping = {
        module.name: dep.label
        for dep in deps
        for module in dep[SwiftInfo].direct_modules
    }

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(ctx.label)

    # Generate a source file that imports each of the deps using `@_exported`.
    reexport_src = derived_files.reexport_modules_src(
        actions = ctx.actions,
        target_name = ctx.label.name,
    )
    ctx.actions.write(
        content = "\n".join([
            "@_exported import {}".format(module)
            for module in module_mapping.keys()
        ]),
        output = reexport_src,
    )

    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    module_context, compilation_outputs, other_compilation_outputs = swift_common.compile(
        actions = ctx.actions,
        copts = ["-parse-as-library"],
        deps = deps,
        feature_configuration = feature_configuration,
        module_name = module_name,
        srcs = [reexport_src],
        swift_toolchain = swift_toolchain,
        target_name = ctx.label.name,
        workspace_name = ctx.workspace_name,
    )

    linking_context, linking_output = (
        swift_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            compilation_outputs = compilation_outputs,
            feature_configuration = feature_configuration,
            label = ctx.label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in deps
                if CcInfo in dep
            ],
            module_context = module_context,
            swift_toolchain = swift_toolchain,
        )
    )

    providers = [
        DefaultInfo(
            files = depset(compact([
                module_context.swift.swiftdoc,
                module_context.swift.swiftinterface,
                module_context.swift.swiftmodule,
                linking_output.library_to_link.pic_static_library,
                linking_output.library_to_link.static_library,
            ])),
        ),
        OutputGroupInfo(**output_groups_from_other_compilation_outputs(
            other_compilation_outputs = other_compilation_outputs,
        )),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
        ),
        CcInfo(
            compilation_context = module_context.clang.compilation_context,
            linking_context = linking_context,
        ),
        swift_common.create_swift_info(
            modules = [module_context],
            swift_infos = get_providers(deps, SwiftInfo),
        ),
    ]

    # Propagate an `apple_common.Objc` provider with linking info about the
    # library so that linking with Apple Starlark APIs/rules works correctly.
    # TODO(b/171413861): This can be removed when the Obj-C rules are migrated
    # to use `CcLinkingContext`.
    providers.append(new_objc_provider(
        additional_objc_infos = (
            swift_toolchain.implicit_deps_providers.objc_infos
        ),
        deps = deps,
        feature_configuration = feature_configuration,
        module_context = module_context,
        libraries_to_link = [linking_output.library_to_link],
    ))

    return providers

swift_module_alias = rule(
    attrs = dicts.add(
        swift_common.toolchain_attrs(),
        {
            "module_name": attr.string(
                doc = """\
The name of the Swift module being built.

If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading `//` and replacing `/`, `:`, and other
non-identifier characters with underscores.
""",
            ),
            "deps": attr.label_list(
                doc = """\
A list of targets that are dependencies of the target being built, which will be
linked into that target. Allowed kinds are `swift_import` and `swift_library`
(or anything else propagating `SwiftInfo`).
""",
                providers = [[SwiftInfo]],
            ),
        },
    ),
    doc = """\
Creates a Swift module that re-exports other modules.

This rule effectively creates an "alias" for one or more modules such that a
client can import the alias module and it will implicitly import those
dependencies. It should be used primarily as a way to migrate users when a
module name is being changed. An alias that depends on more than one module can
be used to split a large module into smaller, more targeted modules.

Symbols in the original modules can be accessed through either the original
module name or the alias module name, so callers can be migrated separately
after moving the physical build target as needed. (An exception to this is
runtime type metadata, which only encodes the module name of the type where the
symbol is defined; it is not repeated by the alias module.)

> Caution: This rule uses the undocumented `@_exported` feature to re-export the
> `deps` in the new module. You depend on undocumented features at your own
> risk, as they may change in a future version of Swift.
""",
    fragments = ["cpp"],
    implementation = _swift_module_alias_impl,
)

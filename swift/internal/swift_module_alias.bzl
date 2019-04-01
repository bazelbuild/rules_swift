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
load(":api.bzl", "swift_common")
load(":derived_files.bzl", "derived_files")
load(":providers.bzl", "SwiftInfo", "SwiftToolchainInfo")

def _swift_module_alias_impl(ctx):
    module_mapping = {dep[SwiftInfo].module_name: dep.label for dep in ctx.attr.deps}

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(ctx.label)

    # Print a warning message directing users to the new modules that they need to
    # import. This "nag" is intended to prevent users from misusing this rule to
    # simply forward imported modules.
    warning = """\n
WARNING: The Swift target \"{target}\" (defining module {module_name}) is \
deprecated. Please update your BUILD targets and Swift code to import the \
following dependencies instead:\n\n""".format(
        target = str(ctx.label),
        module_name = module_name,
    )
    for dep_module_name, dep_target in module_mapping.items():
        warning += '  - "{target}" (import {module_name})\n'.format(
            target = str(dep_target),
            module_name = dep_module_name,
        )
    print(warning + "\n")

    # Generate a source file that imports each of the deps using `@_exported`.
    reexport_src = derived_files.reexport_modules_src(ctx.actions, ctx.label.name)
    ctx.actions.write(
        content = "\n".join([
            "@_exported import {}".format(module)
            for module in module_mapping.keys()
        ]),
        output = reexport_src,
    )

    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = swift_common.configure_features(
        requested_features = ctx.features,
        swift_toolchain = toolchain,
        unsupported_features = ctx.disabled_features,
    )

    compile_results = swift_common.compile_as_library(
        actions = ctx.actions,
        bin_dir = ctx.bin_dir,
        label = ctx.label,
        module_name = module_name,
        srcs = [reexport_src],
        toolchain = ctx.attr._toolchain[SwiftToolchainInfo],
        deps = ctx.attr.deps,
        feature_configuration = feature_configuration,
        genfiles_dir = ctx.genfiles_dir,
    )

    return compile_results.providers + [
        DefaultInfo(
            files = depset(direct = [
                compile_results.output_archive,
                compile_results.output_doc,
                compile_results.output_module,
            ]),
        ),
        OutputGroupInfo(**compile_results.output_groups),
    ]

swift_module_alias = rule(
    attrs = dicts.add(
        swift_common.toolchain_attrs(),
        {
            "module_name": attr.string(
                doc = """
The name of the Swift module being built.

If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading `//` and replacing `/`, `:`, and other
non-identifier characters with underscores.
""",
            ),
            "deps": attr.label_list(
                doc = """
A list of targets that are dependencies of the target being built, which will be
linked into that target. Allowed kinds are `swift_import` and `swift_library`
(or anything else propagating `SwiftInfo`).
""",
                providers = [[SwiftInfo]],
            ),
        },
    ),
    doc = """
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

This rule unconditionally prints a message directing users to migrate from the
alias to the aliased modules---this is intended to prevent misuse of this rule
to create "umbrella modules".

> Caution: This rule uses the undocumented `@_exported` feature to re-export the
> `deps` in the new module. You depend on undocumented features at your own
> risk, as they may change in a future version of Swift.
""",
    implementation = _swift_module_alias_impl,
)

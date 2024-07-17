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
load(
    "//swift/internal:attrs.bzl",
    "swift_common_rule_attrs",
    "swift_toolchain_attrs",
)
load("//swift/internal:linking.bzl", "new_objc_provider")
load("//swift/internal:toolchain_utils.bzl", "use_swift_toolchain")
load(
    "//swift/internal:utils.bzl",
    "compact",
    "get_compilation_contexts",
    "get_providers",
)
load(":providers.bzl", "SwiftInfo")
load(":swift_common.bzl", "swift_common")

def _swift_import_impl(ctx):
    archives = ctx.files.archives
    deps = ctx.attr.deps
    swiftdoc = ctx.file.swiftdoc
    swiftinterface = ctx.file.swiftinterface
    swiftmodule = ctx.file.swiftmodule

    swift_toolchain = swift_common.get_toolchain(ctx)
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        swift_toolchain = swift_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    if not (swiftinterface or swiftmodule):
        fail("One of 'swiftinterface' or 'swiftmodule' must be " +
             "specified.")

    if swiftinterface and swiftmodule:
        fail("'swiftinterface' may not be specified when " +
             "'swiftmodule' is specified.")

    swift_toolchain = swift_common.get_toolchain(ctx)
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        swift_toolchain = swift_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    libraries_to_link = [
        cc_common.create_library_to_link(
            actions = ctx.actions,
            cc_toolchain = swift_toolchain.cc_toolchain_info,
            feature_configuration = swift_common.cc_feature_configuration(
                feature_configuration,
            ),
            static_library = archive,
        )
        for archive in archives
    ]
    linker_input = cc_common.create_linker_input(
        owner = ctx.label,
        libraries = depset(libraries_to_link),
    )
    linking_context = cc_common.create_linking_context(
        linker_inputs = depset([linker_input]),
    )
    cc_info = cc_common.merge_cc_infos(
        direct_cc_infos = [CcInfo(linking_context = linking_context)],
        cc_infos = [dep[CcInfo] for dep in deps if CcInfo in dep],
    )

    swift_infos = get_providers(deps, SwiftInfo)

    if swiftinterface:
        module_context = swift_common.compile_module_interface(
            actions = ctx.actions,
            compilation_contexts = get_compilation_contexts(ctx.attr.deps),
            feature_configuration = feature_configuration,
            module_name = ctx.attr.module_name,
            swiftinterface_file = swiftinterface,
            swift_infos = swift_infos,
            swift_toolchain = swift_toolchain,
            target_name = ctx.attr.name,
        )
        swift_outputs = [
            module_context.swift.swiftmodule,
        ] + compact([module_context.swift.swiftdoc])
    else:
        module_context = swift_common.create_module(
            name = ctx.attr.module_name,
            clang = swift_common.create_clang_module(
                compilation_context = cc_info.compilation_context,
                module_map = None,
            ),
            swift = swift_common.create_swift_module(
                swiftdoc = swiftdoc,
                swiftmodule = swiftmodule,
            ),
        )
        swift_outputs = [swiftmodule] + compact([swiftdoc])

    providers = [
        DefaultInfo(
            files = depset(archives + swift_outputs),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        cc_info,
        # Propagate an `Objc` provider so that Apple-specific rules like
        # apple_binary` will link the imported library properly. Typically we'd
        # want to only propagate this if the toolchain reports that it supports
        # Objective-C interop, but we would hit the same cyclic dependency
        # mentioned above, so we propagate it unconditionally; it will be
        # ignored on non-Apple platforms anyway.
        new_objc_provider(
            deps = deps,
            feature_configuration = None,
            is_test = ctx.attr.testonly,
            libraries_to_link = libraries_to_link,
            module_context = module_context,
            swift_toolchain = swift_toolchain,
        ),
        swift_common.create_swift_info(
            modules = [module_context],
            swift_infos = swift_infos,
        ),
    ]

    return providers

swift_import = rule(
    attrs = dicts.add(
        swift_common_rule_attrs(),
        swift_toolchain_attrs(),
        {
            "archives": attr.label_list(
                allow_empty = True,
                allow_files = ["a"],
                doc = """\
The list of `.a` files provided to Swift targets that depend on this target.
""",
                mandatory = False,
            ),
            "module_name": attr.string(
                doc = "The name of the module represented by this target.",
                mandatory = True,
            ),
            "swiftdoc": attr.label(
                allow_single_file = ["swiftdoc"],
                doc = """\
The `.swiftdoc` file provided to Swift targets that depend on this target.
""",
                mandatory = False,
            ),
            "swiftinterface": attr.label(
                allow_single_file = ["swiftinterface"],
                doc = """\
The `.swiftinterface` file that defines the module interface for this target.
May not be specified if `swiftmodule` is specified.
""",
                mandatory = False,
            ),
            "swiftmodule": attr.label(
                allow_single_file = ["swiftmodule"],
                doc = """\
The `.swiftmodule` file provided to Swift targets that depend on this target.
May not be specified if `swiftinterface` is specified.
""",
                mandatory = False,
            ),
        },
    ),
    doc = """\
Allows for the use of Swift textual module interfaces or precompiled Swift modules as dependencies in other
`swift_library` and `swift_binary` targets.

To use `swift_import` targets across Xcode versions and/or OS versions, it is required to use `.swiftinterface` files.
These can be produced by the pre-built target if built with:

  - `--features=swift.enable_library_evolution`
  - `--features=swift.emit_swiftinterface`

If the pre-built target supports `.private.swiftinterface` files, these can be used instead of `.swiftinterface` files
in the `swiftinterface` attribute.

To import pre-built Swift modules that use `@_spi` when using `swiftinterface`,
the `.private.swiftinterface` files are required in order to build any code that uses the API marked with `@_spi`.
""",
    fragments = ["cpp"],
    implementation = _swift_import_impl,
    toolchains = use_swift_toolchain(),
)

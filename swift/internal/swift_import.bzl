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
load(":providers.bzl", "SwiftInfo")
load(":swift_common.bzl", "swift_common")
load(":utils.bzl", "compact", "get_providers")

def _swift_import_impl(ctx):
    archives = ctx.files.archives
    deps = ctx.attr.deps
    swiftdoc = ctx.file.swiftdoc
    swiftmodule = ctx.file.swiftmodule

    # We have to depend on the C++ toolchain directly here to create the
    # libraries to link. Depending on the Swift toolchain causes a problematic
    # cyclic dependency for built-from-source toolchains.
    cc_toolchain = ctx.attr._cc_toolchain[cc_common.CcToolchainInfo]
    cc_feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    libraries_to_link = [
        cc_common.create_library_to_link(
            actions = ctx.actions,
            cc_toolchain = cc_toolchain,
            feature_configuration = cc_feature_configuration,
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

    providers = [
        DefaultInfo(
            files = depset(archives + [swiftmodule] + compact([swiftdoc])),
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
            libraries_to_link = libraries_to_link,
            module_context = module_context,
        ),
        swift_common.create_swift_info(
            modules = [module_context],
            swift_infos = get_providers(deps, SwiftInfo),
        ),
    ]

    return providers

swift_import = rule(
    attrs = dicts.add(
        swift_common_rule_attrs(),
        {
            "archives": attr.label_list(
                allow_empty = False,
                allow_files = ["a"],
                doc = """\
The list of `.a` files provided to Swift targets that depend on this target.
""",
                mandatory = True,
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
            "swiftmodule": attr.label(
                allow_single_file = ["swiftmodule"],
                doc = """\
The `.swiftmodule` file provided to Swift targets that depend on this target.
""",
                mandatory = True,
            ),
            "_cc_toolchain": attr.label(
                default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
                doc = """\
The C++ toolchain from which linking flags and other tools needed by the Swift
toolchain (such as `clang`) will be retrieved.
""",
            ),
        },
    ),
    doc = """\
Allows for the use of precompiled Swift modules as dependencies in other
`swift_library` and `swift_binary` targets.
""",
    fragments = ["cpp"],
    implementation = _swift_import_impl,
)

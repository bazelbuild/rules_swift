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
    "@build_bazel_rules_swift//swift/internal:attrs.bzl",
    "swift_common_rule_attrs",
    "swift_toolchain_attrs",
)
load(
    "@build_bazel_rules_swift//swift/internal:compiling.bzl",
    "compile_module_interface",
)
load(
    "@build_bazel_rules_swift//swift/internal:features.bzl",
    "configure_features",
    "get_cc_feature_configuration",
)
load(
    "@build_bazel_rules_swift//swift/internal:toolchain_utils.bzl",
    "get_swift_toolchain",
    "use_swift_toolchain",
)
load(
    "@build_bazel_rules_swift//swift/internal:utils.bzl",
    "compact",
    "get_compilation_contexts",
    "get_providers",
)
load(
    ":providers.bzl",
    "SwiftInfo",
    "create_clang_module_inputs",
    "create_swift_module_context",
    "create_swift_module_inputs",
)

visibility("public")

def _swift_import_impl(ctx):
    archives = ctx.files.archives
    deps = ctx.attr.deps
    swiftdoc = ctx.file.swiftdoc
    swiftinterface = ctx.file.swiftinterface
    swiftmodule = ctx.file.swiftmodule

    if not (swiftinterface or swiftmodule):
        fail("One or both of 'swiftinterface' and 'swiftmodule' must be " +
             "specified.")

    swift_toolchain = get_swift_toolchain(ctx, attr = "toolchain")
    feature_configuration = configure_features(
        ctx = ctx,
        swift_toolchain = swift_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    libraries_to_link = [
        cc_common.create_library_to_link(
            actions = ctx.actions,
            cc_toolchain = swift_toolchain.cc_toolchain_info,
            feature_configuration = get_cc_feature_configuration(
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

    if swiftinterface and not swiftmodule:
        module_context = compile_module_interface(
            actions = ctx.actions,
            compilation_contexts = get_compilation_contexts(ctx.attr.deps),
            feature_configuration = feature_configuration,
            module_name = ctx.attr.module_name,
            swiftinterface_file = swiftinterface,
            swift_infos = swift_infos,
            swift_toolchain = swift_toolchain,
        )
        swift_outputs = [
            module_context.swift.swiftmodule,
        ] + compact([module_context.swift.swiftdoc])
    else:
        module_context = create_swift_module_context(
            name = ctx.attr.module_name,
            clang = create_clang_module_inputs(
                compilation_context = cc_info.compilation_context,
                module_map = None,
            ),
            swift = create_swift_module_inputs(
                swiftdoc = swiftdoc,
                swiftmodule = swiftmodule,
            ),
        )
        swift_outputs = [swiftmodule] + compact([swiftdoc])

    return [
        DefaultInfo(
            files = depset(archives + swift_outputs),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        SwiftInfo(
            modules = [module_context],
            swift_infos = swift_infos,
        ),
        cc_info,
    ]

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
""",
                mandatory = False,
            ),
            "swiftmodule": attr.label(
                allow_single_file = ["swiftmodule"],
                doc = """\
The `.swiftmodule` file provided to Swift targets that depend on this target.
""",
                mandatory = False,
            ),
        },
    ),
    doc = """\
Allows for the use of Swift textual module interfaces and/or precompiled Swift modules as dependencies in other
`swift_library` and `swift_binary` targets.
""",
    fragments = ["cpp"],
    implementation = _swift_import_impl,
    toolchains = use_swift_toolchain(),
)

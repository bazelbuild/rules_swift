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
"""An aspect attached to `proto_library` targets to generate Swift artifacts."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "@build_bazel_rules_swift//swift:module_name.bzl",
    "derive_swift_module_name",
)
load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftInfo",
    "SwiftProtoInfo",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_proto//proto:defs.bzl", "ProtoInfo", "proto_common")
load(":attrs.bzl", "swift_config_attrs")
load(":compiling.bzl", "compile")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_LAYERING_CHECK_SWIFT",
)
load(":features.bzl", "configure_features")
load(":linking.bzl", "create_linking_context_from_compilation_outputs")
load(":output_groups.bzl", "supplemental_compilation_output_groups")
load(":proto_gen_utils.bzl", "swift_proto_lang_toolchain_label")
load(":toolchain_utils.bzl", "find_all_toolchains", "use_all_toolchains")
load(":utils.bzl", "get_compilation_contexts")

visibility([
    "@build_bazel_rules_swift//swift/...",
])

SwiftProtoCompilationInfo = provider(
    doc = """\
Wraps compilation related providers added to a `proto_library` by the aspect.

This is necessary because `proto_library` targets already propagate a `CcInfo`
provider for C++ protos; but `swift_proto_library` also wants to attach Swift
related providers, some other languages that also provide Swift interop might
also needs to provide Swift providers for their langauges to interop. So the
Swift proto aspect wraps all the providers it use in this provider to "hide"
them from other langauges, and then `swift_proto_library` extracts all the
nested providers and returns them as its providers since that is where these
specific apis are exposed in the build graph.

This provider is an implementation detail not meant to be used by clients.
""",
    fields = {
        "cc_info": "The underlying `CcInfo` provider.",
        "swift_info": "The underlying `SwiftInfo` provider.",
    },
)

# Name of the execution group used for `ProtocGenSwift` actions.
_GENERATE_EXEC_GROUP = "generate"

def _build_module_mapping_from_srcs(module_name, proto_srcs):
    """Returns the sequence of module mapping `struct`s for the given sources.

    Args:
        module_name: The module name of the `proto_library` target being
            compiled.
        proto_srcs: The `.proto` files that belong to the target.

    Returns:
        A string containing the module mapping for the target in protobuf text
        format.
    """

    return struct(
        module_name = module_name,
        proto_file_paths = [
            proto_common.get_import_path(f)
            for f in proto_srcs
        ],
    )

def _register_module_mapping_write_action(name, actions, module_mappings):
    """Registers an action that generates a module mapping for a proto library.

    Args:
        name: The name of the target being analyzed.
        actions: The context's actions object.
        module_mappings: The `depset` of module mapping `struct`s to be rendered.
            This sequence should already have duplicates removed.

    Returns:
        The `File` representing the module mapping that will be generated in
        protobuf text format.
    """
    mapping_file = actions.declare_file(
        "{}.protoc_gen_swift_modules.asciipb".format(name),
    )
    content = actions.args()
    content.set_param_file_format("multiline")
    content.add_all(module_mappings, map_each = _render_text_module_mapping)

    actions.write(
        content = content,
        output = mapping_file,
    )

    return mapping_file

def _render_text_module_mapping(mapping):
    """Renders the text format proto for a module mapping.

    Args:
        mapping: A single module mapping `struct`.

    Returns:
        A string containing the module mapping for the target in protobuf text
        format.
    """
    module_name = mapping.module_name
    proto_file_paths = mapping.proto_file_paths

    content = "mapping {\n"
    content += '  module_name: "%s"\n' % module_name
    if len(proto_file_paths) == 1:
        content += '  proto_file_path: "%s"\n' % proto_file_paths[0]
    else:
        # Use list form to avoid parsing and looking up the field name for each
        # entry.
        content += '  proto_file_path: [\n    "%s"' % proto_file_paths[0]
        for path in proto_file_paths[1:]:
            content += ',\n    "%s"' % path
        content += "\n  ]\n"
    content += "}\n"

    return content

def _swift_protoc_gen_aspect_impl(target, aspect_ctx):
    toolchains = find_all_toolchains(aspect_ctx)
    proto_lang_toolchain_info = aspect_ctx.attr._proto_lang_toolchain[proto_common.ProtoLangToolchainInfo]
    target_proto_info = target[ProtoInfo]

    if proto_common.experimental_should_generate_code(
        proto_info = target_proto_info,
        proto_lang_toolchain_info = proto_lang_toolchain_info,
        rule_name = "swift_proto_library",
        target_label = target.label,
    ):
        direct_pbswift_files = proto_common.declare_generated_files(
            actions = aspect_ctx.actions,
            proto_info = target_proto_info,
            extension = ".pb.swift",
        )
    else:
        direct_pbswift_files = []

    proto_deps = aspect_ctx.rule.attr.deps
    transitive_cc_infos = []
    transitive_swift_infos = []
    transitive_module_mappings = []
    transitive_pbswift_files = []
    for p in proto_deps:
        compilation_info = p[SwiftProtoCompilationInfo]
        transitive_cc_infos.append(compilation_info.cc_info)
        transitive_swift_infos.append(compilation_info.swift_info)
        swift_proto_info = p[SwiftProtoInfo]
        transitive_module_mappings.append(swift_proto_info.module_mappings)
        transitive_pbswift_files.append(swift_proto_info.pbswift_files)

    direct_module_mappings = []
    if direct_pbswift_files:
        feature_configuration = configure_features(
            ctx = aspect_ctx,
            requested_features = aspect_ctx.features,
            toolchains = toolchains,
            unsupported_features = aspect_ctx.disabled_features + [
                SWIFT_FEATURE_ENABLE_TESTING,
                # Layering checks interfere with `import public`, where the
                # generator explicitly emits imports of modules that may only be
                # transitively available. We can also save some computational
                # effort by not doing the extra work.
                SWIFT_FEATURE_LAYERING_CHECK_SWIFT,
            ],
        )
        module_name = derive_swift_module_name(
            target.label,
            feature_configuration = feature_configuration,
        )
        direct_module_mappings.append(
            _build_module_mapping_from_srcs(
                module_name = module_name,
                proto_srcs = target_proto_info.direct_sources,
            ),
        )

    module_mappings = depset(direct_module_mappings, transitive = transitive_module_mappings)

    if direct_pbswift_files:
        transitive_module_mapping_file = _register_module_mapping_write_action(
            target.label.name,
            aspect_ctx.actions,
            module_mappings,
        )

        extra_args = aspect_ctx.actions.args()
        extra_args.add("--swift_opt=FileNaming=FullPath")
        extra_args.add("--swift_opt=Visibility=Public")
        extra_args.add(
            transitive_module_mapping_file,
            format = "--swift_opt=ProtoPathModuleMappings=%s",
        )
        proto_common.compile(
            actions = aspect_ctx.actions,
            additional_args = extra_args,
            additional_inputs = depset(direct = [transitive_module_mapping_file]),
            experimental_exec_group = _GENERATE_EXEC_GROUP,
            generated_files = direct_pbswift_files,
            proto_info = target_proto_info,
            proto_lang_toolchain_info = proto_lang_toolchain_info,
        )

        # Compile the generated Swift sources and produce a static library and a
        # .swiftmodule as outputs. In addition to the other proto deps, we also
        # pass support libraries like the SwiftProtobuf runtime as deps to the
        # compile action.
        support_deps = [proto_lang_toolchain_info.runtime]
        for p in support_deps:
            if CcInfo in p:
                transitive_cc_infos.append(p[CcInfo])
            if SwiftInfo in p:
                transitive_swift_infos.append(p[SwiftInfo])

        compile_result = compile(
            actions = aspect_ctx.actions,
            compilation_contexts = get_compilation_contexts(support_deps),
            copts = ["-parse-as-library"],
            feature_configuration = feature_configuration,
            module_name = module_name,
            srcs = direct_pbswift_files,
            swift_infos = transitive_swift_infos,
            toolchains = toolchains,
            target_name = target.label.name,
        )

        module_context = compile_result.module_context
        compilation_outputs = compile_result.compilation_outputs
        supplemental_outputs = compile_result.supplemental_outputs

        linking_context, _ = (
            create_linking_context_from_compilation_outputs(
                actions = aspect_ctx.actions,
                compilation_outputs = compilation_outputs,
                feature_configuration = feature_configuration,
                label = target.label,
                linking_contexts = [x.linking_context for x in transitive_cc_infos],
                module_context = module_context,
                # Prevent conflicts with C++ protos in the same output
                # directory, which use the `lib{name}.a` pattern. This will
                # produce `lib{name}.swift.a` instead.
                name = "{}.swift".format(target.label.name),
                toolchains = toolchains,
            )
        )

        cc_info = CcInfo(
            compilation_context = module_context.clang.compilation_context,
            linking_context = linking_context,
        )

        providers = [
            OutputGroupInfo(
                **supplemental_compilation_output_groups(supplemental_outputs)
            ),
            SwiftProtoCompilationInfo(
                cc_info = cc_info,
                swift_info = compile_result.swift_info,
            ),
        ]
    else:
        # If there are no srcs, merge the `SwiftInfo` and `CcInfo` providers and
        # propagate them. Note that we don't need to handle the runtime support
        # libraries here; we can assume that they've already been pulled in by a
        # `proto_library` that had srcs.
        #
        # NOTE: `swift_proto_library` won't allow itself to depend on a
        # `proto_library` with no `srcs`, but this case can happen in the
        # transitive `proto_library` graph so the merging behavior is needed
        # for things that depend on such targets.
        if len(transitive_cc_infos) == 1 and len(transitive_swift_infos) == 1:
            providers = [
                SwiftProtoCompilationInfo(
                    cc_info = transitive_cc_infos[0],
                    swift_info = transitive_swift_infos[0],
                ),
            ]
        else:
            providers = [
                SwiftProtoCompilationInfo(
                    cc_info = cc_common.merge_cc_infos(
                        cc_infos = transitive_cc_infos,
                    ),
                    swift_info = SwiftInfo(swift_infos = transitive_swift_infos),
                ),
            ]

    providers.append(SwiftProtoInfo(
        module_mappings = module_mappings,
        pbswift_files = depset(
            direct = direct_pbswift_files,
            transitive = transitive_pbswift_files,
        ),
    ))

    return providers

swift_protoc_gen_aspect = aspect(
    attr_aspects = ["deps"],
    attrs = dicts.add(
        swift_config_attrs(),
        {
            "_proto_lang_toolchain": attr.label(
                default = swift_proto_lang_toolchain_label(),
            ),
        },
    ),
    doc = """\
Generates Swift artifacts for a `proto_library` target.

For each `proto_library` (more specifically, any target that propagates a
`proto` provider) to which this aspect is applied, the aspect will register
actions that generate Swift artifacts and propagate them in a `SwiftProtoInfo`
provider.

Most users should not need to use this aspect directly; it is an implementation
detail of the `swift_proto_library` rule.
""",
    exec_groups = {
        # Define an execution group for `ProtocGenSwift` actions that does not
        # have constraints, so that proto generation can be routed to any
        # platform that supports it (even one with a different toolchain).
        _GENERATE_EXEC_GROUP: exec_group(),
    },
    provides = [SwiftProtoInfo],
    fragments = ["cpp"],
    implementation = _swift_protoc_gen_aspect_impl,
    toolchains = use_all_toolchains(),
)

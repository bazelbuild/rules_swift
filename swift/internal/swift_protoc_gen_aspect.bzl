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

load(
    "@build_bazel_rules_swift//swift:module_name.bzl",
    "derive_swift_module_name",
)
load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftInfo",
    "SwiftProtoInfo",
)
load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_proto//proto:defs.bzl", "ProtoInfo", "proto_common")
load(":attrs.bzl", "swift_config_attrs", "swift_toolchain_attrs")
load(":compiling.bzl", "compile")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_LAYERING_CHECK_SWIFT",
)
load(":features.bzl", "configure_features")
load(":linking.bzl", "create_linking_context_from_compilation_outputs")
load(
    ":proto_gen_utils.bzl",
    "proto_import_path",
    "register_module_mapping_write_action",
)
load(":toolchain_utils.bzl", "get_swift_toolchain", "use_swift_toolchain")
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

def _is_well_known_types_target(target_label):
    """Checks if the given label is an WKT target..

    Args:
        target_label: A Label for the target.

    Returns:
        `True` if the Label seems to be a WKT target.
    """

    # Keeping this simple, anything in their WORKSPACE we'll treat as a WKT.
    # This can be tweaked in the future if need be to also check the `package`.
    return target_label.workspace_name == "com_google_protobuf"

def _build_swift_proto_info_provider(
        pbswift_files,
        transitive_module_mappings,
        deps):
    """Builds the `SwiftProtoInfo` provider to propagate for a proto library.

    Args:
        pbswift_files: The `.pb.swift` files that were generated for the
            propagating target. This sequence should only contain the direct
            sources.
        transitive_module_mappings: A sequence of `structs` with `module_name`
            and `proto_file_paths` fields that denote the transitive mappings
            from `.proto` files to Swift modules.
        deps: The direct dependencies of the propagating target, from which the
            transitive sources will be computed.

    Returns:
        An instance of `SwiftProtoInfo`.
    """
    return SwiftProtoInfo(
        module_mappings = transitive_module_mappings,
        pbswift_files = depset(
            direct = pbswift_files,
            transitive = [dep[SwiftProtoInfo].pbswift_files for dep in deps],
        ),
    )

def _build_module_mapping_from_srcs(target, proto_srcs, proto_source_root):
    """Returns the sequence of module mapping `struct`s for the given sources.

    Args:
        target: The `proto_library` target whose module mapping is being
            rendered.
        proto_srcs: The `.proto` files that belong to the target.
        proto_source_root: The source root for `proto_srcs`.

    Returns:
        A string containing the module mapping for the target in protobuf text
        format.
    """

    # TODO: Need a way to get proto import paths to reduce the custom logic.
    # TODO(allevato): The previous use of f.short_path here caused problems with
    # cross-repo references; protoc-gen-swift only processes the file correctly
    # if the workspace-relative path is used (which is the same as the
    # short_path for same-repo references, so this issue had never been caught).
    # However, this implies that if two repos have protos with the same
    # workspace-relative paths, there will be a clash. Figure out what to do
    # here; it may require an update to protoc-gen-swift?
    return struct(
        module_name = derive_swift_module_name(target.label),
        proto_file_paths = [
            proto_import_path(f, proto_source_root)
            for f in proto_srcs
        ],
    )

def _gather_transitive_module_mappings(targets):
    """Returns the set of transitive module mappings for the given targets.

    This function eliminates duplicates among the targets so that if two or more
    targets transitively depend on the same `proto_library`, the mapping is only
    present in the sequence once.

    Args:
        targets: The targets whose module mappings should be returned.

    Returns:
        A sequence containing the transitive module mappings for the given
        targets, without duplicates.
    """
    unique_mappings = {}

    for target in targets:
        mappings = target[SwiftProtoInfo].module_mappings
        for mapping in mappings:
            module_name = mapping.module_name
            if module_name not in unique_mappings:
                unique_mappings[module_name] = mapping.proto_file_paths

    return [struct(
        module_name = module_name,
        proto_file_paths = file_paths,
    ) for module_name, file_paths in unique_mappings.items()]

def _swift_protoc_gen_aspect_impl(target, aspect_ctx):
    swift_toolchain = get_swift_toolchain(aspect_ctx)
    proto_lang_toolchain_info = aspect_ctx.attr._proto_lang_toolchain[proto_common.ProtoLangToolchainInfo]
    target_proto_info = target[ProtoInfo]

    # TODO: `proto_common` doesn't have non-experimental apis for filtering out
    # the bundled files, so use our own check.
    if _is_well_known_types_target(target.label):
        # WKTs bundled with the runtime.
        pbswift_files = []
    else:
        pbswift_files = proto_common.declare_generated_files(
            actions = aspect_ctx.actions,
            proto_info = target_proto_info,
            extension = ".pb.swift",
        )

    proto_deps = aspect_ctx.rule.attr.deps
    transitive_cc_infos = []
    transitive_swift_infos = []
    for p in proto_deps:
        compilation_info = p[SwiftProtoCompilationInfo]
        transitive_cc_infos.append(compilation_info.cc_info)
        transitive_swift_infos.append(compilation_info.swift_info)

    minimal_module_mappings = []
    if pbswift_files:
        minimal_module_mappings.append(
            _build_module_mapping_from_srcs(
                target,
                target_proto_info.direct_sources,
                target_proto_info.proto_source_root,
            ),
        )
    if proto_deps:
        minimal_module_mappings.extend(
            _gather_transitive_module_mappings(proto_deps),
        )

    if pbswift_files:
        transitive_module_mapping_file = register_module_mapping_write_action(
            target.label.name,
            aspect_ctx.actions,
            minimal_module_mappings,
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
            generated_files = pbswift_files,
            proto_info = target_proto_info,
            proto_lang_toolchain_info = proto_lang_toolchain_info,
        )

        extra_features = []

        # This feature is not fully supported because the SwiftProtobuf library
        # has not yet been designed to fully support library evolution. The
        # intent of this is to allow users building distributable frameworks to
        # use Swift protos as an _implementation-only_ detail of their
        # framework, where those protos would not be exposed to clients in the
        # API. Rely on it at your own risk.
        if aspect_ctx.attr._config_emit_swiftinterface[BuildSettingInfo].value:
            extra_features.append(SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION)
            extra_features.append(SWIFT_FEATURE_EMIT_SWIFTINTERFACE)

        # Compile the generated Swift sources and produce a static library and a
        # .swiftmodule as outputs. In addition to the other proto deps, we also
        # pass support libraries like the SwiftProtobuf runtime as deps to the
        # compile action.
        feature_configuration = configure_features(
            ctx = aspect_ctx,
            requested_features = aspect_ctx.features + extra_features,
            swift_toolchain = swift_toolchain,
            unsupported_features = aspect_ctx.disabled_features + [
                SWIFT_FEATURE_ENABLE_TESTING,
                # Layering checks interfere with `import public`, where the
                # generator explicitly emits imports of modules that may only be
                # transitively available. We can also save some computational
                # effort by not doing the extra work.
                SWIFT_FEATURE_LAYERING_CHECK_SWIFT,
            ],
        )

        module_name = derive_swift_module_name(target.label)

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
            srcs = pbswift_files,
            swift_infos = transitive_swift_infos,
            swift_toolchain = swift_toolchain,
            target_name = target.label.name,
        )

        module_context = compile_result.module_context
        compilation_outputs = compile_result.compilation_outputs
        supplemental_outputs = compile_result.supplemental_outputs

        output_groups = {}
        if supplemental_outputs.indexstore_directory:
            output_groups["indexstore"] = depset([
                supplemental_outputs.indexstore_directory,
            ])

        linking_context, _ = (
            create_linking_context_from_compilation_outputs(
                actions = aspect_ctx.actions,
                # No protocol conformances, single source per file, so require linker references.
                alwayslink = False,
                compilation_outputs = compilation_outputs,
                feature_configuration = feature_configuration,
                label = target.label,
                linking_contexts = [x.linking_context for x in transitive_cc_infos],
                module_context = module_context,
                # Prevent conflicts with C++ protos in the same output
                # directory, which use the `lib{name}.a` pattern. This will
                # produce `lib{name}.swift.a` instead.
                name = "{}.swift".format(target.label.name),
                swift_toolchain = swift_toolchain,
            )
        )

        cc_info = CcInfo(
            compilation_context = module_context.clang.compilation_context,
            linking_context = linking_context,
        )

        providers = [
            OutputGroupInfo(**output_groups),
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

        providers = [
            SwiftProtoCompilationInfo(
                cc_info = cc_common.merge_cc_infos(
                    cc_infos = transitive_cc_infos,
                ),
                swift_info = SwiftInfo(swift_infos = transitive_swift_infos),
            ),
        ]

    providers.append(_build_swift_proto_info_provider(
        pbswift_files,
        minimal_module_mappings,
        proto_deps,
    ))

    return providers

swift_protoc_gen_aspect = aspect(
    attr_aspects = ["deps"],
    attrs = dicts.add(
        swift_toolchain_attrs(),
        swift_config_attrs(),
        {
            "_proto_lang_toolchain": attr.label(
                default = Label("@build_bazel_rules_swift//swift/internal:proto_swift_toolchain"),
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
    fragments = ["cpp"],
    implementation = _swift_protoc_gen_aspect_impl,
    toolchains = use_swift_toolchain(),
)

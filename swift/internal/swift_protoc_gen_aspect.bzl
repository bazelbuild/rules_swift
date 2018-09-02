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
load(":api.bzl", "swift_common")
load(":features.bzl", "SWIFT_FEATURE_ENABLE_TESTING", "SWIFT_FEATURE_NO_GENERATED_HEADER")
load(":linking.bzl", "register_libraries_to_link")
load(
    ":proto_gen_utils.bzl",
    "declare_generated_files",
    "extract_generated_dir_path",
    "register_module_mapping_write_action",
)
load(":providers.bzl", "SwiftInfo", "SwiftProtoInfo", "SwiftToolchainInfo")
load(":utils.bzl", "compact", "create_cc_info", "get_providers", "workspace_relative_path")

# The paths of proto files bundled with the runtime. This is mainly the well
# known type protos, but also includes descriptor.proto to make generation of
# files that include options easier. These files should not be generated by
# the aspect because they are already included in the SwiftProtobuf runtime.
# The plugin provides the mapping from these protos to the SwiftProtobuf
# module for us.
# TODO(b/63389580): Once we migrate to proto_lang_toolchain, this information
# can go in the blacklisted_protos list instead.
_RUNTIME_BUNDLED_PROTO_FILES = [
    "google/protobuf/any.proto",
    "google/protobuf/api.proto",
    "google/protobuf/descriptor.proto",
    "google/protobuf/duration.proto",
    "google/protobuf/empty.proto",
    "google/protobuf/field_mask.proto",
    "google/protobuf/source_context.proto",
    "google/protobuf/struct.proto",
    "google/protobuf/timestamp.proto",
    "google/protobuf/type.proto",
    "google/protobuf/wrappers.proto",
]

SwiftProtoCcInfo = provider(
    doc = """
Wraps a `CcInfo` provider added to a `proto_library` through the Swift proto aspect.

This is necessary because `proto_library` targets already propagate a `CcInfo` provider for C++
protos, so the Swift proto aspect cannot directly attach its own. (It's also not good practice
to attach providers that you don't own to arbitrary targets, because you don't know how those
targets might change in the future.) The `swift_proto_library` rule will pick up this provider
and return the underlying `CcInfo` provider as its own.

This provider is an implementation detail not meant to be used by clients.
""",
    fields = {
        "cc_info": "The underlying `CcInfo` provider.",
        "objc_info": "The underlying `apple_common.Objc` provider.",
    },
)

def _filter_out_well_known_types(srcs):
    """Returns the given list of files, excluding any well-known type protos.

    Args:
      srcs: A list of `.proto` files.

    Returns:
      The given list of files with any well-known type protos (those living under
      the `google.protobuf` package) removed.
    """
    return [
        f
        for f in srcs
        if workspace_relative_path(f) not in _RUNTIME_BUNDLED_PROTO_FILES
    ]

def _register_pbswift_generate_action(
        label,
        actions,
        direct_srcs,
        transitive_descriptor_sets,
        module_mapping_file,
        mkdir_and_run,
        protoc_executable,
        protoc_plugin_executable):
    """Registers the actions that generate `.pb.swift` files from `.proto` files.

    Args:
        label: The label of the target being analyzed.
        actions: The context's actions object.
        direct_srcs: The direct `.proto` sources belonging to the target being analyzed, which
            will be passed to `protoc-gen-swift`.
        transitive_descriptor_sets: The transitive `DescriptorSet`s from the `proto_library` being
            analyzed.
        module_mapping_file: The `File` containing the mapping between `.proto` files and Swift
            modules for the transitive dependencies of the target being analyzed. May be `None`, in
            which case no module mapping will be passed (the case for leaf nodes in the dependency
            graph).
        mkdir_and_run: The `File` representing the `mkdir_and_run` executable.
        protoc_executable: The `File` representing the `protoc` executable.
        protoc_plugin_executable: The `File` representing the `protoc` plugin executable.

    Returns:
        A list of generated `.pb.swift` files corresponding to the `.proto` sources.
    """
    generated_files = declare_generated_files(label.name, actions, "pb", direct_srcs)
    generated_dir_path = extract_generated_dir_path(label.name, "pb", generated_files)

    mkdir_args = actions.args()
    mkdir_args.add(generated_dir_path)

    protoc_executable_args = actions.args()
    protoc_executable_args.add(protoc_executable)

    protoc_args = actions.args()

    # protoc takes an arg of @NAME as something to read, and expects one
    # arg per line in that file.
    protoc_args.set_param_file_format("multiline")
    protoc_args.use_param_file("@%s")

    protoc_args.add(
        protoc_plugin_executable,
        format = "--plugin=protoc-gen-swift=%s",
    )
    protoc_args.add(generated_dir_path, format = "--swift_out=%s")
    protoc_args.add("--swift_opt=FileNaming=PathToUnderscores")
    protoc_args.add("--swift_opt=Visibility=Public")
    if module_mapping_file:
        protoc_args.add(
            module_mapping_file,
            format = "--swift_opt=ProtoPathModuleMappings=%s",
        )
    protoc_args.add("--descriptor_set_in")
    protoc_args.add_joined(transitive_descriptor_sets, join_with = ":")
    protoc_args.add_all([workspace_relative_path(f) for f in direct_srcs])

    additional_command_inputs = []
    if module_mapping_file:
        additional_command_inputs.append(module_mapping_file)

    # TODO(b/23975430): This should be a simple `actions.run_shell`, but until the
    # cited bug is fixed, we have to use the wrapper script.
    actions.run(
        arguments = [mkdir_args, protoc_executable_args, protoc_args],
        executable = mkdir_and_run,
        inputs = depset(
            direct = additional_command_inputs,
            transitive = [transitive_descriptor_sets],
        ),
        mnemonic = "ProtocGenSwift",
        outputs = generated_files,
        progress_message = "Generating Swift sources for {}".format(label),
        tools = [
            mkdir_and_run,
            protoc_executable,
            protoc_plugin_executable,
        ],
    )

    return generated_files

def _build_swift_proto_info_provider(
        pbswift_files,
        transitive_module_mappings,
        deps):
    """Builds the `SwiftProtoInfo` provider to propagate for a proto library.

    Args:
      pbswift_files: The `.pb.swift` files that were generated for the propagating
          target. This sequence should only contain the direct sources.
      transitive_module_mappings: A sequence of `structs` with `module_name` and
          `proto_file_paths` fields that denote the transitive mappings from
          `.proto` files to Swift modules.
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

def _build_module_mapping_from_srcs(target, proto_srcs):
    """Returns the sequence of module mapping `struct`s for the given sources.

    Args:
      target: The `proto_library` target whose module mapping is being rendered.
      proto_srcs: The `.proto` files that belong to the target.

    Returns:
      A string containing the module mapping for the target in protobuf text
      format.
    """

    # TODO(allevato): The previous use of f.short_path here caused problems with
    # cross-repo references; protoc-gen-swift only processes the file correctly if
    # the workspace-relative path is used (which is the same as the short_path for
    # same-repo references, so this issue had never been caught). However, this
    # implies that if two repos have protos with the same workspace-relative
    # paths, there will be a clash. Figure out what to do here; it may require an
    # update to protoc-gen-swift?
    return struct(
        module_name = swift_common.derive_module_name(target.label),
        proto_file_paths = [workspace_relative_path(f) for f in proto_srcs],
    )

def _gather_transitive_module_mappings(targets):
    """Returns the set of transitive module mappings for the given targets.

    This function eliminates duplicates among the targets so that if two or more
    targets transitively depend on the same `proto_library`, the mapping is only
    present in the sequence once.

    Args:
      targets: The targets whose module mappings should be returned.

    Returns:
      A sequence containing the transitive module mappings for the given targets,
      without duplicates.
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
    swift_toolchain = aspect_ctx.attr._toolchain[SwiftToolchainInfo]

    direct_srcs = _filter_out_well_known_types(target[ProtoInfo].direct_sources)

    # Direct sources are passed as arguments to protoc to generate *only* the
    # files in this target, but we need to pass the transitive sources as inputs
    # to the generating action so that all the dependent files are available for
    # protoc to parse.
    # Instead of providing all those files and opening/reading them, we use
    # protoc's support for reading descriptor sets to resolve things.
    transitive_descriptor_sets = target[ProtoInfo].transitive_descriptor_sets
    proto_deps = [dep for dep in aspect_ctx.rule.attr.deps if SwiftProtoInfo in dep]

    minimal_module_mappings = []
    if direct_srcs:
        minimal_module_mappings.append(
            _build_module_mapping_from_srcs(target, direct_srcs),
        )
    if proto_deps:
        minimal_module_mappings.extend(_gather_transitive_module_mappings(proto_deps))

    transitive_module_mapping_file = register_module_mapping_write_action(
        target,
        aspect_ctx.actions,
        minimal_module_mappings,
    )

    support_deps = aspect_ctx.attr._proto_support

    if direct_srcs:
        # Generate the Swift sources from the .proto files.
        pbswift_files = _register_pbswift_generate_action(
            target.label,
            aspect_ctx.actions,
            direct_srcs,
            transitive_descriptor_sets,
            transitive_module_mapping_file,
            aspect_ctx.executable._mkdir_and_run,
            aspect_ctx.executable._protoc,
            aspect_ctx.executable._protoc_gen_swift,
        )

        # Compile the generated Swift sources and produce a static library and a
        # .swiftmodule as outputs. In addition to the other proto deps, we also pass
        # support libraries like the SwiftProtobuf runtime as deps to the compile
        # action.
        feature_configuration = swift_common.configure_features(
            ctx = aspect_ctx,
            requested_features = aspect_ctx.features + [SWIFT_FEATURE_NO_GENERATED_HEADER],
            swift_toolchain = swift_toolchain,
            unsupported_features = aspect_ctx.disabled_features + [SWIFT_FEATURE_ENABLE_TESTING],
        )

        module_name = swift_common.derive_module_name(target.label)

        compilation_outputs = swift_common.compile(
            actions = aspect_ctx.actions,
            bin_dir = aspect_ctx.bin_dir,
            copts = ["-parse-as-library"],
            deps = proto_deps + support_deps,
            feature_configuration = feature_configuration,
            genfiles_dir = aspect_ctx.genfiles_dir,
            module_name = module_name,
            srcs = pbswift_files,
            swift_toolchain = swift_toolchain,
            target_name = target.label.name,
        )

        library_to_link = register_libraries_to_link(
            actions = aspect_ctx.actions,
            alwayslink = False,
            cc_feature_configuration = swift_common.cc_feature_configuration(
                feature_configuration = feature_configuration,
            ),
            is_dynamic = False,
            is_static = True,
            # Prevent conflicts with C++ protos in the same output directory, which
            # use the `lib{name}.a` pattern. This will produce `lib{name}.swift.a`
            # instead.
            library_name = "{}.swift".format(target.label.name),
            objects = compilation_outputs.object_files,
            swift_toolchain = swift_toolchain,
        )

        # It's bad practice to attach providers you don't own to other targets, because you can't
        # control how those targets might change in the future (e.g., it could introduce a
        # collision). This means we can't propagate a `CcInfo` from this aspect nor do we want to
        # merge the `CcInfo` providers from the target's deps. Instead, the aspect returns a
        # `SwiftProtoCcInfo` provider that wraps the `CcInfo` containing the Swift linking info.
        # Then, for any subgraph of `proto_library` targets, we can merge the extracted `CcInfo`
        # providers with the regular `CcInfo` providers of the support libraries (which are regular
        # `swift_library` targets), and wrap that *back* into a `SwiftProtoCcInfo`. Finally, the
        # `swift_proto_library` rule will extract the `CcInfo` from the `SwiftProtoCcInfo` of its
        # single dependency and propagate that safely up the tree.
        cc_infos = (
            get_providers(proto_deps, SwiftProtoCcInfo, _extract_cc_info) +
            get_providers(support_deps, CcInfo)
        )

        # Propagate an `objc` provider if the toolchain supports Objective-C interop, which ensures
        # that the libraries get linked into `apple_binary` targets properly.
        if swift_toolchain.supports_objc_interop:
            objc_infos = get_providers(
                proto_deps,
                SwiftProtoCcInfo,
                _extract_objc_info,
            ) + get_providers(support_deps, apple_common.Objc)

            objc_info_args = {}
            if compilation_outputs.generated_header:
                objc_info_args["header"] = depset([compilation_outputs.generated_header])
            if library_to_link.pic_static_library:
                objc_info_args["library"] = depset(
                    [library_to_link.pic_static_library],
                    order = "topological",
                )
            if compilation_outputs.linker_flags:
                objc_info_args["linkopt"] = depset(compilation_outputs.linker_flags)
            if compilation_outputs.generated_module_map:
                objc_info_args["module_map"] = depset([compilation_outputs.generated_module_map])

            linker_inputs = (
                compilation_outputs.linker_inputs + compact([compilation_outputs.swiftmodule])
            )
            if linker_inputs:
                objc_info_args["link_inputs"] = depset(linker_inputs)

            objc_info = apple_common.new_objc_provider(
                include = depset([aspect_ctx.bin_dir.path]),
                providers = objc_infos,
                uses_swift = True,
                **objc_info_args
            )
        else:
            objc_info = None

        output_groups = {}
        if compilation_outputs.stats_directory:
            output_groups["swift_compile_stats_direct"] = depset(
                [compilation_outputs.stats_directory],
            )

        providers = [
            OutputGroupInfo(**output_groups),
            SwiftProtoCcInfo(
                cc_info = create_cc_info(
                    cc_infos = cc_infos,
                    compilation_outputs = compilation_outputs,
                    libraries_to_link = [library_to_link],
                ),
                objc_info = objc_info,
            ),
            swift_common.create_swift_info(
                module_name = module_name,
                swiftdocs = [compilation_outputs.swiftdoc],
                swiftmodules = [compilation_outputs.swiftmodule],
                swift_infos = get_providers(proto_deps + support_deps, SwiftInfo),
            ),
        ]
    else:
        # If there are no srcs, merge the `SwiftInfo` and `CcInfo` providers and propagate them. Do
        # likewise for `apple_common.Objc` providers if the toolchain supports Objective-C interop.
        # Note that we don't need to handle the runtime support libraries here; we can assume that
        # they've already been pulled in by a `proto_library` that had srcs.
        pbswift_files = []

        if swift_toolchain.supports_objc_interop:
            objc_providers = get_providers(proto_deps, SwiftProtoCcInfo, _extract_objc_info)
            objc_provider = apple_common.new_objc_provider(providers = objc_providers)
            objc_info = objc_provider
        else:
            objc_info = None

        providers = [
            SwiftProtoCcInfo(
                cc_info = cc_common.merge_cc_infos(
                    cc_infos = get_providers(proto_deps, SwiftProtoCcInfo, _extract_cc_info),
                ),
                objc_info = objc_info,
            ),
            swift_common.create_swift_info(
                swift_infos = get_providers(proto_deps, SwiftInfo),
            ),
        ]

    providers.append(_build_swift_proto_info_provider(
        pbswift_files,
        minimal_module_mappings,
        proto_deps,
    ))

    return providers

def _extract_cc_info(proto_cc_info):
    """A map function for `get_providers` to extract the `CcInfo` from a `SwiftProtoCcInfo`.

    Args:
        proto_cc_info: A `SwiftProtoCcInfo` provider.

    Returns:
        The `CcInfo` nested inside the `SwiftProtoCcInfo`.
    """
    return proto_cc_info.cc_info

def _extract_objc_info(proto_cc_info):
    """A map function for `get_providers` to extract the `Objc` provider from a `SwiftProtoCcInfo`.

    Args:
        proto_cc_info: A `SwiftProtoCcInfo` provider.

    Returns:
        The `ObjcInfo` nested inside the `SwiftProtoCcInfo`.
    """
    return proto_cc_info.objc_info

swift_protoc_gen_aspect = aspect(
    attr_aspects = ["deps"],
    attrs = dicts.add(
        swift_common.toolchain_attrs(),
        {
            "_mkdir_and_run": attr.label(
                cfg = "host",
                default = Label(
                    "@build_bazel_rules_swift//tools/mkdir_and_run",
                ),
                executable = True,
            ),
            # TODO(b/63389580): Migrate to proto_lang_toolchain.
            "_proto_support": attr.label_list(
                default = [
                    Label("@com_github_apple_swift_protobuf//:SwiftProtobuf"),
                ],
            ),
            "_protoc": attr.label(
                cfg = "host",
                default = Label("@com_google_protobuf//:protoc"),
                executable = True,
            ),
            "_protoc_gen_swift": attr.label(
                cfg = "host",
                default = Label("@com_github_apple_swift_protobuf//:ProtoCompilerPlugin"),
                executable = True,
            ),
        },
    ),
    doc = """
Generates Swift artifacts for a `proto_library` target.

For each `proto_library` (more specifically, any target that propagates a
`proto` provider) to which this aspect is applied, the aspect will register
actions that generate Swift artifacts and propagate them in a `SwiftProtoInfo`
provider.

Most users should not need to use this aspect directly; it is an implementation
detail of the `swift_proto_library` rule.
""",
    fragments = ["cpp"],
    implementation = _swift_protoc_gen_aspect_impl,
)

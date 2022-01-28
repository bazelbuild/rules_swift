# Copyright 2019 The Bazel Authors. All rights reserved.
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

"""A Swift library rule that generates gRPC services defined in protos."""

load("@rules_proto//proto:defs.bzl", "ProtoInfo")
load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    ":compiling.bzl",
    "new_objc_provider",
    "output_groups_from_other_compilation_outputs",
)
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_GENERATE_FROM_RAW_PROTO_FILES",
)
load(
    ":proto_gen_utils.bzl",
    "declare_generated_files",
    "extract_generated_dir_path",
    "proto_import_path",
    "register_module_mapping_write_action",
)
load(":providers.bzl", "SwiftInfo", "SwiftProtoInfo", "SwiftToolchainInfo")
load(":swift_common.bzl", "swift_common")
load(":utils.bzl", "compact", "get_providers")

def _register_grpcswift_generate_action(
        label,
        actions,
        direct_srcs,
        proto_source_root,
        transitive_descriptor_sets,
        module_mapping_file,
        generate_from_proto_sources,
        mkdir_and_run,
        protoc_executable,
        protoc_plugin_executable,
        flavor,
        extra_module_imports):
    """Registers actions to generate `.grpc.swift` files from `.proto` files.

    Args:
        label: The label of the target being analyzed.
        actions: The context's actions object.
        direct_srcs: The direct `.proto` sources belonging to the target being
            analyzed, which will be passed to `protoc`.
        proto_source_root: the source root for `direct_srcs`.
        transitive_descriptor_sets: The transitive `DescriptorSet`s from the
            `proto_library` being analyzed.
        module_mapping_file: The `File` containing the mapping between `.proto`
            files and Swift modules for the transitive dependencies of the
            target being analyzed. May be `None`, in which case no module
            mapping will be passed (the case for leaf nodes in the dependency
            graph).
        generate_from_proto_sources: True/False for is generation should happen
            from proto source file vs just via the DescriptorSets. The Sets
            don't have source info, so the generated sources won't have
            comments (https://github.com/bazelbuild/bazel/issues/9337).
        mkdir_and_run: The `File` representing the `mkdir_and_run` executable.
        protoc_executable: The `File` representing the `protoc` executable.
        protoc_plugin_executable: The `File` representing the `protoc` plugin
            executable.
        flavor: The library flavor to generate.
        extra_module_imports: Additional modules to import.

    Returns:
        A list of generated `.grpc.swift` files corresponding to the `.proto`
        sources.
    """
    generated_files = declare_generated_files(
        label.name,
        actions,
        "grpc",
        proto_source_root,
        direct_srcs,
    )
    generated_dir_path = extract_generated_dir_path(
        label.name,
        "grpc",
        proto_source_root,
        generated_files,
    )

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
        format = "--plugin=protoc-gen-swiftgrpc=%s",
    )
    protoc_args.add(generated_dir_path, format = "--swiftgrpc_out=%s")
    protoc_args.add("--swiftgrpc_opt=Visibility=Public")
    if flavor == "client":
        protoc_args.add("--swiftgrpc_opt=Client=true")
        protoc_args.add("--swiftgrpc_opt=Server=false")
    elif flavor == "client_stubs":
        protoc_args.add("--swiftgrpc_opt=Client=true")
        protoc_args.add("--swiftgrpc_opt=Server=false")
        protoc_args.add("--swiftgrpc_opt=TestStubs=true")
        protoc_args.add("--swiftgrpc_opt=Implementations=false")
    elif flavor == "server":
        protoc_args.add("--swiftgrpc_opt=Client=false")
        protoc_args.add("--swiftgrpc_opt=Server=true")
    else:
        fail("Unsupported swift_grpc_library flavor", attr = "flavor")
    protoc_args.add_all(
        extra_module_imports,
        format_each = "--swiftgrpc_opt=ExtraModuleImports=%s",
    )
    if module_mapping_file:
        protoc_args.add(
            module_mapping_file,
            format = "--swiftgrpc_opt=ProtoPathModuleMappings=%s",
        )

    protoc_args.add_joined(
        transitive_descriptor_sets,
        join_with = ":",
        format_joined = "--descriptor_set_in=%s",
        omit_if_empty = True,
    )

    if generate_from_proto_sources:
        # ProtoCompileActionBuilder.java's XPAND_TRANSITIVE_PROTO_PATH_FLAGS
        # leaves this off also.
        if proto_source_root != ".":
            protoc_args.add(proto_source_root, format = "--proto_path=%s")

        # Follow ProtoCompileActionBuilder.java's
        # ExpandImportArgsFn::expandToCommandLine() logic and provide a mapping
        # for each file to the proto path.
        for f in direct_srcs:
            protoc_args.add("-I%s=%s" % (proto_import_path(f, proto_source_root), f.path))

    protoc_args.add_all([
        proto_import_path(f, proto_source_root)
        for f in direct_srcs
    ])

    additional_command_inputs = []
    if generate_from_proto_sources:
        additional_command_inputs.extend(direct_srcs)
    if module_mapping_file:
        additional_command_inputs.append(module_mapping_file)

    # TODO(b/23975430): This should be a simple `actions.run_shell`, but until
    # the cited bug is fixed, we have to use the wrapper script.
    actions.run(
        arguments = [mkdir_args, protoc_executable_args, protoc_args],
        executable = mkdir_and_run,
        inputs = depset(
            direct = additional_command_inputs,
            transitive = [transitive_descriptor_sets],
        ),
        tools = [
            mkdir_and_run,
            protoc_executable,
            protoc_plugin_executable,
        ],
        mnemonic = "ProtocGenSwiftGRPC",
        outputs = generated_files,
        progress_message = "Generating Swift sources for %{label}",
    )

    return generated_files

def _swift_grpc_library_impl(ctx):
    if len(ctx.attr.deps) != 1:
        fail(
            "You must list exactly one target in the deps attribute.",
            attr = "deps",
        )
    if len(ctx.attr.srcs) != 1:
        fail(
            "You must list exactly one target in the srcs attribute.",
            attr = "srcs",
        )

    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]

    unsupported_features = ctx.disabled_features
    if ctx.attr.flavor != "client_stubs":
        unsupported_features.append(SWIFT_FEATURE_ENABLE_TESTING)

    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = unsupported_features,
    )

    generate_from_proto_sources = swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_GENERATE_FROM_RAW_PROTO_FILES,
    )

    srcs_proto_info = ctx.attr.srcs[0][ProtoInfo]

    # Only the files for direct sources should be generated, but the
    # transitive descriptor sets are still need to be able to parse/load
    # those descriptors.
    direct_srcs = srcs_proto_info.direct_sources
    if generate_from_proto_sources:
        # Take the transitive descriptor sets from the proto_library deps,
        # so the direct sources won't be in any descriptor sets to reduce
        # the input to the action (and what protoc has to parse).
        direct_descriptor_set = srcs_proto_info.direct_descriptor_set
        transitive_descriptor_sets = depset(direct = [
            x
            for x in srcs_proto_info.transitive_descriptor_sets.to_list()
            if x != direct_descriptor_set
        ])
    else:
        transitive_descriptor_sets = srcs_proto_info.transitive_descriptor_sets

    deps = ctx.attr.deps

    minimal_module_mappings = deps[0][SwiftProtoInfo].module_mappings
    transitive_module_mapping_file = register_module_mapping_write_action(
        ctx.label.name,
        ctx.actions,
        minimal_module_mappings,
    )

    extra_module_imports = []
    if ctx.attr.flavor == "client_stubs":
        extra_module_imports.append(swift_common.derive_module_name(deps[0].label))

    # Generate the Swift sources from the .proto files.
    generated_files = _register_grpcswift_generate_action(
        ctx.label,
        ctx.actions,
        direct_srcs,
        srcs_proto_info.proto_source_root,
        transitive_descriptor_sets,
        transitive_module_mapping_file,
        generate_from_proto_sources,
        ctx.executable._mkdir_and_run,
        ctx.executable._protoc,
        ctx.executable._protoc_gen_swiftgrpc,
        ctx.attr.flavor,
        extra_module_imports,
    )

    # Compile the generated Swift sources and produce a static library and a
    # .swiftmodule as outputs. In addition to the other proto deps, we also pass
    # support libraries like the SwiftProtobuf runtime as deps to the compile
    # action.
    compile_deps = deps + ctx.attr._proto_support

    module_name = swift_common.derive_module_name(ctx.label)

    module_context, cc_compilation_outputs, other_compilation_outputs = swift_common.compile(
        actions = ctx.actions,
        copts = ["-parse-as-library"],
        deps = compile_deps,
        feature_configuration = feature_configuration,
        module_name = module_name,
        srcs = generated_files,
        swift_toolchain = swift_toolchain,
        target_name = ctx.label.name,
        workspace_name = ctx.workspace_name,
    )

    linking_context, linking_output = (
        swift_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            compilation_outputs = cc_compilation_outputs,
            feature_configuration = feature_configuration,
            label = ctx.label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in compile_deps
                if CcInfo in dep
            ],
            module_context = module_context,
            swift_toolchain = swift_toolchain,
        )
    )

    providers = [
        DefaultInfo(
            files = depset(direct = generated_files + compact([
                module_context.swift.swiftdoc,
                module_context.swift.swiftmodule,
                linking_output.library_to_link.pic_static_library,
                linking_output.library_to_link.static_library,
            ])),
        ),
        OutputGroupInfo(**output_groups_from_other_compilation_outputs(
            other_compilation_outputs = other_compilation_outputs,
        )),
        CcInfo(
            compilation_context = module_context.clang.compilation_context,
            linking_context = linking_context,
        ),
        deps[0][SwiftProtoInfo],
        swift_common.create_swift_info(
            modules = [module_context],
            swift_infos = get_providers(compile_deps, SwiftInfo),
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
        deps = compile_deps,
        feature_configuration = feature_configuration,
        module_context = module_context,
        libraries_to_link = [linking_output.library_to_link],
    ))

    return providers

swift_grpc_library = rule(
    attrs = dicts.add(
        swift_common.toolchain_attrs(),
        {
            "srcs": attr.label_list(
                doc = """\
Exactly one `proto_library` target that defines the services being generated.
""",
                providers = [ProtoInfo],
            ),
            "deps": attr.label_list(
                doc = """\
Exactly one `swift_proto_library` or `swift_grpc_library` target that contains
the Swift protos used by the services being generated. Test stubs should depend
on the `swift_grpc_library` implementing the service.
""",
                providers = [[SwiftInfo, SwiftProtoInfo]],
            ),
            "flavor": attr.string(
                values = [
                    "client",
                    "client_stubs",
                    "server",
                ],
                mandatory = True,
                doc = """\
The kind of definitions that should be generated:

*   `"client"` to generate client definitions.

*   `"client_stubs"` to generate client test stubs.

*   `"server"` to generate server definitions.
""",
            ),
            "_mkdir_and_run": attr.label(
                cfg = "exec",
                default = Label(
                    "@build_bazel_rules_swift//tools/mkdir_and_run",
                ),
                executable = True,
            ),
            # TODO(b/63389580): Migrate to proto_lang_toolchain.
            "_proto_support": attr.label_list(
                default = [Label("@com_github_grpc_grpc_swift//:SwiftGRPC")],
            ),
            "_protoc": attr.label(
                cfg = "exec",
                default = Label(
                    "@com_google_protobuf//:protoc",
                ),
                executable = True,
            ),
            "_protoc_gen_swiftgrpc": attr.label(
                cfg = "exec",
                default = Label(
                    "@com_github_grpc_grpc_swift//:protoc-gen-swiftgrpc_wrapper",
                ),
                executable = True,
            ),
        },
    ),
    doc = """\
Generates a Swift library from gRPC services defined in protocol buffer sources.

There should be one `swift_grpc_library` for any `proto_library` that defines
services. A target based on this rule can be used as a dependency anywhere that
a `swift_library` can be used.

We recommend that `swift_grpc_library` targets be located in the same package as
the `proto_library` and `swift_proto_library` targets they depend on. For more
best practices around the use of Swift protocol buffer build rules, see the
documentation for `swift_proto_library`.

#### Defining Build Targets for Services

Note that `swift_grpc_library` only generates the gRPC service interfaces (the
`service` definitions) from the `.proto` files. Any messages defined in the same
`.proto` file must be generated using a `swift_proto_library` target. Thus, the
typical structure of a Swift gRPC library is similar to the following:

```python
proto_library(
    name = "my_protos",
    srcs = ["my_protos.proto"],
)

# Generate Swift types from the protos.
swift_proto_library(
    name = "my_protos_swift",
    deps = [":my_protos"],
)

# Generate Swift types from the services.
swift_grpc_library(
    name = "my_protos_client_services_swift",

    # The `srcs` attribute points to the `proto_library` containing the service
    # definitions...
    srcs = [":my_protos"],

    # ...the `flavor` attribute specifies the kind of definitions to generate...
    flavor = "client",

    # ...and the `deps` attribute points to the `swift_proto_library` that was
    # generated from the same `proto_library` and which contains the messages
    # used by those services.
    deps = [":my_protos_swift"],
)

# Generate test stubs from swift services.
swift_grpc_library(
    name = "my_protos_client_stubs_swift",

    # The `srcs` attribute points to the `proto_library` containing the service
    # definitions...
    srcs = [":my_protos"],

    # ...the `flavor` attribute specifies the kind of definitions to generate...
    flavor = "client_stubs",

    # ...and the `deps` attribute points to the `swift_grpc_library` that was
    # generated from the same `proto_library` and which contains the service
    # implementation.
    deps = [":my_protos_client_services_swift"],
)
```
""",
    fragments = ["cpp"],
    implementation = _swift_grpc_library_impl,
)

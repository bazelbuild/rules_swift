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

"""A rule that generates a Swift library from gRPC services defined in protobuf sources."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(":api.bzl", "swift_common")
load(":features.bzl", "SWIFT_FEATURE_ENABLE_TESTING", "SWIFT_FEATURE_NO_GENERATED_HEADER")
load(
    ":proto_gen_utils.bzl",
    "declare_generated_files",
    "extract_generated_dir_path",
    "register_module_mapping_write_action",
)
load(":providers.bzl", "SwiftInfo", "SwiftProtoInfo", "SwiftToolchainInfo")
load(":utils.bzl", "workspace_relative_path")

def _register_grpcswift_generate_action(
        label,
        actions,
        direct_srcs,
        transitive_descriptor_sets,
        module_mapping_file,
        mkdir_and_run,
        protoc_executable,
        protoc_plugin_executable,
        flavor,
        extra_module_imports):
    """Registers the actions that generate `.grpc.swift` files from `.proto` files.

    Args:
        label: The label of the target being analyzed.
        actions: The context's actions object.
        direct_srcs: The direct `.proto` sources belonging to the target being analyzed, which
            will be passed to `protoc`.
        transitive_descriptor_sets: The transitive `DescriptorSet`s from the `proto_library` being
            analyzed.
        module_mapping_file: The `File` containing the mapping between `.proto` files and Swift
            modules for the transitive dependencies of the target being analyzed. May be `None`, in
            which case no module mapping will be passed (the case for leaf nodes in the dependency
            graph).
        mkdir_and_run: The `File` representing the `mkdir_and_run` executable.
        protoc_executable: The `File` representing the `protoc` executable.
        protoc_plugin_executable: The `File` representing the `protoc` plugin executable.
        flavor: The library flavor to generate.
        extra_module_imports: Additional modules to import.

    Returns:
        A list of generated `.grpc.swift` files corresponding to the `.proto` sources.
    """
    generated_files = declare_generated_files(label.name, actions, "grpc", direct_srcs)
    generated_dir_path = extract_generated_dir_path(label.name, "grpc", generated_files)

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
        tools = [
            mkdir_and_run,
            protoc_executable,
            protoc_plugin_executable,
        ],
        mnemonic = "ProtocGenSwiftGRPC",
        outputs = generated_files,
        progress_message = "Generating Swift sources for {}".format(label),
    )

    return generated_files

def _swift_grpc_library_impl(ctx):
    if len(ctx.attr.deps) != 1:
        fail("You must list exactly one target in the deps attribute.", attr = "deps")
    if len(ctx.attr.srcs) != 1:
        fail("You must list exactly one target in the srcs attribute.", attr = "srcs")

    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]

    # Direct sources are passed as arguments to protoc to generate *only* the
    # files in this target, but we need to pass the transitive sources as inputs
    # to the generating action so that all the dependent files are available for
    # protoc to parse.
    # Instead of providing all those files and opening/reading them, we use
    # protoc's support for reading descriptor sets to resolve things.
    direct_srcs = ctx.attr.srcs[0][ProtoInfo].direct_sources
    transitive_descriptor_sets = ctx.attr.srcs[0][ProtoInfo].transitive_descriptor_sets
    deps = ctx.attr.deps

    minimal_module_mappings = deps[0][SwiftProtoInfo].module_mappings
    transitive_module_mapping_file = register_module_mapping_write_action(
        ctx.label.name,
        ctx.actions,
        minimal_module_mappings,
    )

    extra_module_imports = []
    if ctx.attr.flavor == "client_stubs":
        extra_module_imports += [swift_common.derive_module_name(deps[0].label)]

    # Generate the Swift sources from the .proto files.
    generated_files = _register_grpcswift_generate_action(
        ctx.label,
        ctx.actions,
        direct_srcs,
        transitive_descriptor_sets,
        transitive_module_mapping_file,
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

    unsupported_features = ctx.disabled_features
    if ctx.attr.flavor != "client_stubs":
        unsupported_features.append(SWIFT_FEATURE_ENABLE_TESTING)

    feature_configuration = swift_common.configure_features(
        requested_features = ctx.features + [SWIFT_FEATURE_NO_GENERATED_HEADER],
        swift_toolchain = toolchain,
        unsupported_features = unsupported_features,
    )

    compile_results = swift_common.compile_as_library(
        actions = ctx.actions,
        bin_dir = ctx.bin_dir,
        label = ctx.label,
        module_name = swift_common.derive_module_name(ctx.label),
        srcs = generated_files,
        toolchain = toolchain,
        deps = compile_deps,
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
        deps[0][SwiftProtoInfo],
    ]

swift_grpc_library = rule(
    attrs = dicts.add(
        swift_common.toolchain_attrs(),
        {
            "srcs": attr.label_list(
                doc = """
Exactly one `proto_library` target that defines the services being generated.
""",
                providers = [ProtoInfo],
            ),
            "deps": attr.label_list(
                doc = """
Exactly one `swift_proto_library` or `swift_grpc_library` target that contains the Swift protos
used by the services being generated. Test stubs should depend on the `swift_grpc_library`
implementing the service.
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
                doc = """
The kind of definitions that should be generated:

* `"client"` to generate client definitions.
* `"client_stubs"` to generate client test stubs.
* `"server"` to generate server definitions.
""",
            ),
            "_mkdir_and_run": attr.label(
                cfg = "host",
                default = Label("@build_bazel_rules_swift//tools/mkdir_and_run"),
                executable = True,
            ),
            # TODO(b/63389580): Migrate to proto_lang_toolchain.
            "_proto_support": attr.label_list(
                default = [Label("@com_github_grpc_grpc_swift//:SwiftGRPC")],
            ),
            "_protoc": attr.label(
                cfg = "host",
                default = Label("@com_google_protobuf//:protoc"),
                executable = True,
            ),
            "_protoc_gen_swiftgrpc": attr.label(
                cfg = "host",
                default = Label("@com_github_grpc_grpc_swift//:protoc-gen-swiftgrpc"),
                executable = True,
            ),
        },
    ),
    doc = """
Generates a Swift library from the gRPC services defined in protocol buffer sources.

There should be one `swift_grpc_library` for any `proto_library` that defines services. A target
based on this rule can be used as a dependency anywhere that a `swift_library` can be used.

We recommend that `swift_grpc_library` targets be located in the same package as the
`proto_library` and `swift_proto_library` targets they depend on. For more best practices around
the use of Swift protocol buffer build rules, see the documentation for `swift_proto_library`.

#### Defining Build Targets for Services

Note that `swift_grpc_library` only generates the gRPC service interfaces (the `service`
definitions) from the `.proto` files. Any messages defined in the same `.proto` file must be
generated using a `swift_proto_library` target. Thus, the typical structure of a Swift gRPC
library is similar to the following:

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
    # The `srcs` attribute points to the `proto_library` containing the service definitions...
    srcs = [":my_protos"],
    # ...the `flavor` attribute specifies what kind of definitions to generate...
    flavor = "client",
    # ...and the `deps` attribute points to the `swift_proto_library` that was generated from
    # the same `proto_library` and which contains the messages used by those services.
    deps = [":my_protos_swift"],
)

# Generate test stubs from swift services.
swift_grpc_library(
    name = "my_protos_client_stubs_swift",
    # The `srcs` attribute points to the `proto_library` containing the service definitions...
    srcs = [":my_protos"],
    # ...the `flavor` attribute specifies what kind of definitions to generate...
    flavor = "client_stubs",
    # ...and the `deps` attribute points to the `swift_grpc_library` that was generated from
    # the same `proto_library` and which contains the service implementation.
    deps = [":my_protos_client_services_swift"],
)
```
""",
    implementation = _swift_grpc_library_impl,
)

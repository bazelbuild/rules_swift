# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""
Defines a rule for compiling Swift source files from proto_libraries.
"""

load(
    "@bazel_skylib//lib:dicts.bzl",
    "dicts",
)
load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load(
    "//swift/internal:providers.bzl",
    "SwiftInfo",
)
load(
    ":swift_proto_utils.bzl",
    "proto_path",
    "register_module_mapping_write_action",
)

SwiftProtoCompilerInfo = provider(
    doc = "Information and dependencies needed to generate Swift code from proto_infos",
    fields = {
        "compile": """A function with the signature:

    def compile(ctx, swift_proto_compiler_info, proto_infos, imports)

Where:
- ctx is the rule's context
- swift_proto_compiler_info is this SwiftProtoCompilerInfo provider
- additional_plugin_options additional options to pass to the plugin
- proto_infos is a list of ProtoInfo providers for proto_infos to compile
- imports is a depset of strings mapping proto import paths to Swift module names

The function should declare output .swift files and actions to generate them.
It should return a list of .swift Files to be compiled by the Go compiler.
""",
        "deps": """List of targets providing SwiftInfo and CcInfo.
These are added as implicit dependencies for any swift_proto_library using this
compiler. Typically, these are proto runtime libraries.

Well Known Types should be added as dependencies of the swift_proto_library
targets as needed to avoid compiling them unnecessarily.
""",
        "internal": "Opaque value containing data used by compile.",
    },
)

def _swift_proto_compile(ctx, swift_proto_compiler_info, additional_plugin_options, proto_infos, imports):
    """Invokes protoc to generate Swift sources for a given set of proto info providers.

    Args:
        ctx: the swift proto library rule's context
        swift_proto_compiler_info: a SwiftProtoCompilerInfo provider.
        additional_plugin_options: additional options passed to the plugin from the rule
        proto_infos: list of ProtoInfo providers to compile.
        imports: depset of dictionaries mapping proto paths to module names

    Returns:
        A list of .swift Files generated by the compiler.
    """

    # Overlay the additional plugin options on top of the default plugin options:
    plugin_options = dicts.add(
        swift_proto_compiler_info.internal.plugin_options,
        additional_plugin_options,
    )

    # Declare the swift files that will be generated:
    swift_srcs = []
    output_directory_path = None
    proto_paths = {}
    transitive_descriptor_sets_list = []
    for proto_info in proto_infos:
        # Collect the transitive descriptor sets from the proto infos:
        transitive_descriptor_sets_list.append(proto_info.transitive_descriptor_sets)

        # Iterate over the proto sources in the proto info to gather information
        # about their proto sources and declare the swift files that will be generated:
        for proto_src in proto_info.check_deps_sources.to_list():
            # Derive the proto path:
            path = proto_path(proto_src, proto_info)
            if path in proto_paths:
                if proto_paths[path] != proto_src:
                    fail("proto files {} and {} have the same import path, {}".format(
                        proto_src.path,
                        proto_paths[path].path,
                        path,
                    ))
                continue
            proto_paths[path] = proto_src

            # Declare the proto file that will be generated:
            suffixes = swift_proto_compiler_info.internal.suffixes
            for suffix in suffixes:
                swift_src_path_without_label_name = paths.replace_extension(path, suffix)

                # Apply the file naming option to the path:
                file_naming_plugin_option = plugin_options["FileNaming"] if "FileNaming" in plugin_options else "FullPath"
                if file_naming_plugin_option == "PathToUnderscores":
                    swift_src_path_without_label_name = swift_src_path_without_label_name.replace("/", "_")
                elif file_naming_plugin_option == "DropPath":
                    swift_src_path_without_label_name = paths.basename(swift_src_path_without_label_name)
                elif file_naming_plugin_option == "FullPath":
                    # This is the default behavior and it leaves the path as-is.
                    pass
                else:
                    fail("unknown file naming plugin option: ", file_naming_plugin_option)

                swift_src_path = paths.join(ctx.label.name, swift_src_path_without_label_name)
                swift_src = ctx.actions.declare_file(swift_src_path)
                swift_srcs.append(swift_src)

                # Grab the output path directory:
                if output_directory_path == None:
                    full_swift_src_path = swift_srcs[0].path
                    output_directory_path = full_swift_src_path.removesuffix("/" + swift_src_path_without_label_name)
    transitive_descriptor_sets = depset(direct = [], transitive = transitive_descriptor_sets_list)

    # Merge all of the proto paths to module name mappings from the imports depset:
    merged_proto_paths_to_module_names = {}
    module_names_to_proto_paths = {}
    for path_to_module_name in imports.to_list():
        components = path_to_module_name.split("=")
        path = components[0]
        module_name = components[1]

        # Ensure there are no conflicts between path to module name mappings,
        # and avoid adding duplicate proto paths to the lists:
        if path in merged_proto_paths_to_module_names:
            if merged_proto_paths_to_module_names[path] != module_name:
                fail("Conflicting module names for proto path: ", path)
            continue

        merged_proto_paths_to_module_names[path] = module_name
        module_proto_paths = module_names_to_proto_paths[module_name] if module_name in module_names_to_proto_paths else []
        module_proto_paths.append(path)
        module_names_to_proto_paths[module_name] = module_proto_paths

    # Write the module mappings to a file:
    module_mappings = []
    for module_name in sorted(module_names_to_proto_paths.keys()):
        proto_file_paths = sorted(module_names_to_proto_paths[module_name])
        module_mapping = struct(
            module_name = module_name,
            proto_file_paths = proto_file_paths,
        )
        module_mappings.append(module_mapping)
    module_mappings_file = register_module_mapping_write_action(ctx.label.name, ctx.actions, module_mappings)

    # Build the arguments for protoc:
    arguments = ctx.actions.args()
    arguments.use_param_file("--param=%s")

    # Add the plugin argument with the provided name to namespace all of the options:
    plugin_name_argument = "--plugin=protoc-gen-{}={}".format(
        swift_proto_compiler_info.internal.plugin_name,
        swift_proto_compiler_info.internal.plugin.path,
    )
    arguments.add(plugin_name_argument)

    # Add the plugin option arguments:
    for plugin_option in plugin_options:
        plugin_option_value = plugin_options[plugin_option]
        plugin_option_argument = "--{}_opt={}={}".format(
            swift_proto_compiler_info.internal.plugin_name,
            plugin_option,
            plugin_option_value,
        )
        arguments.add(plugin_option_argument)

    # Add the module mappings file argument:
    module_mappings_file_argument = "--{}_opt=ProtoPathModuleMappings={}".format(
        swift_proto_compiler_info.internal.plugin_name,
        module_mappings_file.path,
    )
    arguments.add(module_mappings_file_argument)

    # Add the output directory argument:
    output_directory_argument = "--{}_out={}".format(
        swift_proto_compiler_info.internal.plugin_name,
        output_directory_path,
    )
    arguments.add(output_directory_argument)

    # Join the transitive descriptor sets into a single argument separated by colons:
    formatted_descriptor_set_paths = ":".join([f.path for f in transitive_descriptor_sets.to_list()])
    descriptor_set_in_argument = "--descriptor_set_in={}".format(formatted_descriptor_set_paths)
    arguments.add(descriptor_set_in_argument)

    # Finally, add the proto paths:
    arguments.add_all(proto_paths.keys())

    # Run protoc:
    ctx.actions.run(
        inputs = depset(
            direct = [
                swift_proto_compiler_info.internal.protoc,
                swift_proto_compiler_info.internal.plugin,
                module_mappings_file,
            ],
            transitive = [transitive_descriptor_sets],
        ),
        outputs = swift_srcs,
        progress_message = "Generating into %s" % swift_srcs[0].dirname,
        mnemonic = "SwiftProtocGen",
        executable = swift_proto_compiler_info.internal.protoc,
        arguments = [arguments],
    )

    return swift_srcs

def _swift_proto_compiler_impl(ctx):
    return [
        SwiftProtoCompilerInfo(
            deps = ctx.attr.deps,
            compile = _swift_proto_compile,
            internal = struct(
                protoc = ctx.executable.protoc,
                plugin = ctx.executable.plugin,
                plugin_name = ctx.attr.plugin_name,
                plugin_options = ctx.attr.plugin_options,
                suffixes = ctx.attr.suffixes,
            ),
        ),
    ]

swift_proto_compiler = rule(
    implementation = _swift_proto_compiler_impl,
    attrs = {
        "deps": attr.label_list(
            default = [],
            doc = """\
            List of targets providing SwiftInfo and CcInfo.
            These are added as implicit dependencies for any swift_proto_library using this
            compiler. Typically, these are Well Known Types and proto runtime libraries.
            """,
            providers = [SwiftInfo],
        ),
        "protoc": attr.label(
            doc = """\
            A proto compiler executable binary.
            
            E.g.
            "//tools/protoc_wrapper:protoc"

            We provide two compiler targets:
            "//swift/proto:swift_proto"
            "//swift/proto:swift_grpc"

            These targets use this attribute to configure protoc with their respective proto compiler.
            """,
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
        "plugin": attr.label(
            doc = """\
            A proto compiler plugin executable binary.
            
            E.g.
            "//tools/protoc_wrapper:protoc-gen-grpc-swift"
            "//tools/protoc_wrapper:ProtoCompilerPlugin"

            We provide two compiler targets:
            "//swift/proto:swift_proto"
            "//swift/proto:swift_grpc"

            These targets use this attribute to configure protoc with their respective plugins.
            """,
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
        "plugin_name": attr.string(
            doc = """\
            Name of the proto compiler plugin passed to protoc.

            E.g.
            protoc --plugin=protoc-gen-NAME=path/to/plugin/binary

            This name will be used to prefix the option and output directory arguments.

            E.g.
            protoc --plugin=protoc-gen-NAME=path/to/mybinary --NAME_out=OUT_DIR --NAME_opt=Visibility=Public

            See the protobuf API reference for more information: 
            https://protobuf.dev/reference/cpp/api-docs/google.protobuf.compiler.plugin
            """,
            mandatory = True,
        ),
        "plugin_options": attr.string_dict(
            doc = """\
            Dictionary of plugin options passed to the plugin.

            These are prefixed with the plugin_name + "_opt".

            E.g.
            plugin_name = "swift"
            plugin_options = {
                "Visibility": "Public",
                "FileNaming": "FullPath",
            }

            Would be passed to protoc as:
            protoc \
                --plugin=protoc-gen-NAME=path/to/plugin/binary \
                --NAME_opt=Visibility=Public \
                --NAME_opt=FileNaming=FullPath
            """,
            mandatory = True,
        ),
        "suffixes": attr.string_list(
            doc = """\
            Suffix used for Swift files generated by the plugin from protos.

            E.g.
            foo.proto => foo.pb.swift
            foo_service.proto => foo.grpc.swift

            Each compiler target should configure this based on the suffix applied to the generated files.
            """,
            mandatory = True,
        ),
    },
)

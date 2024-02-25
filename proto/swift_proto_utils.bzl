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
Utilities for proto rules.
"""

load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load(
    "//swift:swift.bzl",
    "SwiftInfo",
    "SwiftProtoCompilerInfo",
    "SwiftProtoInfo",
    "SwiftToolchainInfo",
    "swift_common",
)

# buildifier: disable=bzl-visibility
load(
    "//swift/internal:compiling.bzl",
    "output_groups_from_other_compilation_outputs",
)

# buildifier: disable=bzl-visibility
load(
    "//swift/internal:linking.bzl",
    "new_objc_provider",
)

# buildifier: disable=bzl-visibility
load(
    "//swift/internal:utils.bzl",
    "compact",
    "get_providers",
    "include_developer_search_paths",
)

def proto_path(proto_src, proto_info):
    """Derives the string used to import the proto. 

    This is the proto source path within its repository,
    adjusted by `import_prefix` and `strip_import_prefix`.

    Args:
        proto_src: the proto source File.
        proto_info: the ProtoInfo provider.

    Returns:
        An import path string.
    """
    if proto_info.proto_source_root == ".":
        # true if proto sources were generated
        prefix = proto_src.root.path + "/"
    elif proto_info.proto_source_root.startswith(proto_src.root.path):
        # sometimes true when import paths are adjusted with import_prefix
        prefix = proto_info.proto_source_root + "/"
    else:
        # usually true when paths are not adjusted
        prefix = paths.join(proto_src.root.path, proto_info.proto_source_root) + "/"
    if not proto_src.path.startswith(prefix):
        # sometimes true when importing multiple adjusted protos
        return proto_src.path
    return proto_src.path[len(prefix):]

def register_module_mapping_write_action(target_label, actions, module_mappings):
    """Registers an action that generates a module mapping for a proto library.

    Args:
        target_label: The label of the target being analyzed.
        actions: The context's actions object.
        module_mappings: The sequence of module mapping `struct`s to be rendered.
            This sequence should already have duplicates removed.

    Returns:
        The `File` representing the module mapping that will be generated in
        protobuf text format.
    """
    mapping_file = actions.declare_file(
        "{}.protoc_gen_swift_modules.asciipb".format(target_label.name),
    )
    content = "".join([_render_text_module_mapping(m) for m in module_mappings])

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

def generate_module_mappings(module_name, proto_infos, transitive_swift_proto_deps):
    """Generates module mappings from ProtoInfo and SwiftProtoInfo providers.

    Args:
        module_name: Name of the module the direct proto dependencies will be compiled into.
        proto_infos: List of ProtoInfo providers for the direct proto dependencies.
        transitive_swift_proto_deps: Transitive dependencies propagating SwiftProtoInfo providers.
        
    Returns:
        List of module mappings.
    """

    # Collect the direct proto source files from the proto deps and build the module mapping:
    direct_proto_file_paths = []
    for proto_info in proto_infos:
        proto_file_paths = [
            proto_path(proto_src, proto_info)
            for proto_src in proto_info.check_deps_sources.to_list()
        ]
        direct_proto_file_paths.extend(proto_file_paths)
    module_mapping = struct(
        module_name = module_name,
        proto_file_paths = direct_proto_file_paths,
    )

    # Collect the transitive module mappings:
    transitive_module_mappings = []
    for dep in transitive_swift_proto_deps:
        if not SwiftProtoInfo in dep:
            continue
        transitive_module_mappings.extend(dep[SwiftProtoInfo].module_mappings)

    # Create a list combining the direct + transitive module mappings:
    return [module_mapping] + transitive_module_mappings

def compile_protos_for_target(
    ctx,
    attr,
    target_label,
    module_name,
    proto_infos,
    module_mappings,
    compilers,
    additional_compiler_deps = [],
    additional_compiler_info = {}):
    """ Compiles the proto source files from the given ProtoInfo provider into a Swift static library.

    Args:
        ctx: The context of the aspect or rule.
        attr: The attributes of the rule. If running from an aspect, this is not the same as `ctx.attr`.
        target_label: The label of the target for which the module is being compiled.
        module_name: The name of the Swift module that should be compiled from the protos.
        proto_infos: List of `ProtoInfo` providers to compile into the Swift static library.
        module_mappings: List of module mapping structs assigning proto paths to Swift modules.
        compilers: List of swift_proto_compiler targets (or targets propagating `SwiftProtoCompilerInfo` providers).
        additional_compiler_deps: List of additional dependencies to pass to the compilation action.
        additional_compiler_info: Dictionary of additional information passed to the Swift proto compiler.
    
    Returns: 
        Providers:
        DefaultInfo, OutputGroupInfo, CcInfo, SwiftInfo, SwiftProtoInfo, apple_common.Objc
    """
    print("compiling protos for target: ", target_label)

    # Extract the swift toolchain and configure the features:
    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    # Use the proto compiler to compile the swift sources for the proto deps:
    compiler_deps = [d for d in additional_compiler_deps]
    generated_swift_srcs = []
    for swift_proto_compiler_target in compilers:
        swift_proto_compiler_info = swift_proto_compiler_target[SwiftProtoCompilerInfo]
        compiler_deps.extend(swift_proto_compiler_info.compiler_deps)
        generated_swift_srcs.extend(swift_proto_compiler_info.compile(
            ctx = ctx,
            target_label = target_label,
            swift_proto_compiler_info = swift_proto_compiler_info,
            additional_compiler_info = additional_compiler_info,
            proto_infos = proto_infos,
            module_mappings = module_mappings,
        ))

    # Compile the generated Swift source files as a module:
    include_dev_srch_paths = include_developer_search_paths(attr)
    module_context, cc_compilation_outputs, other_compilation_outputs = swift_common.compile(
        actions = ctx.actions,
        copts = ["-parse-as-library"],
        deps = compiler_deps,
        feature_configuration = feature_configuration,
        include_dev_srch_paths = include_dev_srch_paths,
        module_name = module_name,
        package_name = None,
        srcs = generated_swift_srcs,
        swift_toolchain = swift_toolchain,
        target_name = target_label.name,
        workspace_name = ctx.workspace_name,
    )

    # Create the linking context from the compilation outputs:
    linking_context, linking_output = (
        swift_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            compilation_outputs = cc_compilation_outputs,
            feature_configuration = feature_configuration,
            include_dev_srch_paths = include_dev_srch_paths,
            label = target_label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in compiler_deps
                if CcInfo in dep
            ],
            module_context = module_context,
            swift_toolchain = swift_toolchain,
        )
    )

    # Create the providers:
    default_info = DefaultInfo(
        files = depset(compact([
            module_context.swift.swiftdoc,
            module_context.swift.swiftinterface,
            module_context.swift.swiftmodule,
            module_context.swift.swiftsourceinfo,
            linking_output.library_to_link.static_library,
            linking_output.library_to_link.pic_static_library,
        ])),
        runfiles = ctx.runfiles(
            collect_data = True,
            collect_default = True,
            files = getattr(ctx.files, "data", []),
        ),
    )
    output_group_info = OutputGroupInfo(**output_groups_from_other_compilation_outputs(
        other_compilation_outputs = other_compilation_outputs,
    ))
    cc_info = CcInfo(
        compilation_context = module_context.clang.compilation_context,
        linking_context = linking_context,
    )
    swift_info = swift_common.create_swift_info(
        modules = [module_context],
        swift_infos = get_providers(compiler_deps, SwiftInfo),
    )
    swift_proto_info = SwiftProtoInfo(
        module_name = module_name,
        module_mappings = module_mappings,
        direct_pbswift_files = generated_swift_srcs,
        pbswift_files = depset(
            direct = generated_swift_srcs,
            transitive = [dep[SwiftProtoInfo].pbswift_files for dep in compiler_deps if SwiftProtoInfo in dep],
        ),
    )

    # Propagate an `apple_common.Objc` provider with linking info about the
    # library so that linking with Apple Starlark APIs/rules works correctly.
    # TODO(b/171413861): This can be removed when the Obj-C rules are migrated
    # to use `CcLinkingContext`.
    objc_info = new_objc_provider(
        additional_objc_infos = (
            swift_toolchain.implicit_deps_providers.objc_infos
        ),
        deps = compiler_deps,
        feature_configuration = feature_configuration,
        is_test = attr.testonly,
        module_context = module_context,
        libraries_to_link = [linking_output.library_to_link],
        swift_toolchain = swift_toolchain,
    )

    return default_info, output_group_info, cc_info, swift_info, swift_proto_info, objc_info

# The exported `swift_proto_common` module, which defines the public API
# for rules that compile Swift protos.
swift_proto_common = struct(
    proto_path = proto_path,
)

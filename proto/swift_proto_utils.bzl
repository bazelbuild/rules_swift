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

def register_module_mapping_write_action(label, actions, module_mappings):
    """Registers an action that generates a module mapping for a proto library.

    Args:
        label: The label of the target being analyzed.
        actions: The context's actions object.
        module_mappings: The sequence of module mapping `struct`s to be rendered.
            This sequence should already have duplicates removed.

    Returns:
        The `File` representing the module mapping that will be generated in
        protobuf text format.
    """
    mapping_file = actions.declare_file(
        "{}.protoc_gen_swift_modules.asciipb".format(label),
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


def compile_protos_for_target(ctx, module_name, proto_infos, module_mappings):
    """ Compiles the proto source files from the given ProtoInfo provider into a Swift static library.

    Args:
        ctx: Rule's context. Must provide a `_toolchain` label attribute providing `SwiftToolchainInfo`,
            and a `compilers` label list attribute providing `SwiftProtoCompilerInfo`
        module_name: The name of the Swift module that should be compiled from the protos.
        proto_infos: List of `ProtoInfo` providers to compile into a Swift static library.
        module_mappings: List of module mapping structs assigning proto paths to Swift modules.
    
    Returns: 
        Providers:
        DefaultInfo, OutputGroupInfo, CcInfo, SwiftInfo, SwiftProtoInfo, apple_common.Objc
    """

    # Extract the swift toolchain and configure the features:
    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    # Use the proto compiler to compile the swift sources for the proto deps:
    compiler_deps = [d for d in ctx.attr.additional_compiler_deps]
    generated_swift_srcs = []
    for swift_proto_compiler_target in ctx.attr.compilers:
        swift_proto_compiler_info = swift_proto_compiler_target[SwiftProtoCompilerInfo]
        compiler_deps.extend(swift_proto_compiler_info.compiler_deps)
        generated_swift_srcs.extend(swift_proto_compiler_info.compile(
            ctx,
            swift_proto_compiler_info = swift_proto_compiler_info,
            additional_compiler_info = ctx.attr.additional_compiler_info,
            proto_infos = proto_infos,
            module_mappings = module_mappings,
        ))

    # Collect the dependencies for the compile action:
    deps = ctx.attr.deps + compiler_deps

    # Compile the generated Swift source files as a module:
    include_dev_srch_paths = include_developer_search_paths(ctx)
    module_context, cc_compilation_outputs, other_compilation_outputs = swift_common.compile(
        actions = ctx.actions,
        copts = ["-parse-as-library"],
        deps = deps,
        feature_configuration = feature_configuration,
        include_dev_srch_paths = include_dev_srch_paths,
        module_name = module_name,
        package_name = None,
        srcs = generated_swift_srcs,
        swift_toolchain = swift_toolchain,
        target_name = ctx.label.name,
        workspace_name = ctx.workspace_name,
    )

    # Create the linking context from the compilation outputs:
    linking_context, linking_output = (
        swift_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            compilation_outputs = cc_compilation_outputs,
            feature_configuration = feature_configuration,
            include_dev_srch_paths = include_dev_srch_paths,
            label = ctx.label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in deps
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
            files = ctx.files.data,
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
        swift_infos = get_providers(deps, SwiftInfo),
    )
    swift_proto_info = SwiftProtoInfo(
        module_name = module_name,
        module_mappings = module_mappings,
        direct_pbswift_files = generated_swift_srcs,
        pbswift_files = depset(
            direct = generated_swift_srcs,
            transitive = [dep[SwiftProtoInfo].pbswift_files for dep in deps if SwiftProtoInfo in dep],
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
        deps = deps,
        feature_configuration = feature_configuration,
        is_test = ctx.attr.testonly,
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

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

def proto_path(proto_src, proto_info):
    """Derives the string used to import the proto. 

    This is the proto source path within its repository,
    adjusted by import_prefix and strip_import_prefix.

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

    print("module mappings: ", content)

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

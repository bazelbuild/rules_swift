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

"""Utilities for rules/aspects that generate sources from .proto files."""

load("@bazel_skylib//lib:paths.bzl", "paths")

def declare_generated_files(
        name,
        actions,
        extension_fragment,
        proto_source_root,
        proto_srcs):
    """Declares generated `.swift` files from a list of `.proto` files.

    Args:
        name: The name of the target currently being analyzed.
        actions: The context's actions object.
        extension_fragment: An extension fragment that precedes `.swift` on the
            end of the generated files. In other words, the file `foo.proto`
            will generate a file named `foo.{extension_fragment}.swift`.
        proto_source_root: the source root of the `.proto` files in
            `proto_srcs`.
        proto_srcs: A list of `.proto` files.

    Returns:
        A list of files that map one-to-one to `proto_srcs` but with
        `.{extension_fragment}.swift` extensions instead of `.proto`.
    """
    return [
        actions.declare_file(
            _generated_file_path(
                name,
                extension_fragment,
                proto_source_root,
                f,
            ),
        )
        for f in proto_srcs
    ]

def extract_generated_dir_path(
        name,
        extension_fragment,
        proto_source_root,
        generated_files):
    """Extracts the full path to the directory where files are generated.

    This dance is required because we cannot get the full (repository-relative)
    path to the directory that we need to pass to `protoc` unless we either
    create the directory as a tree artifact or extract it from a file within
    that directory. We cannot do the former because we also want to declare
    individual outputs for the files we generate, and we can't declare a
    directory that has the same prefix as any of the files we generate. So, we
    assume we have at least one file and we extract the path from it.

    Args:
        name: The name of the target currently being analyzed.
        extension_fragment: An extension fragment that precedes `.swift` on the
            end of the generated files. In other words, the file `foo.proto`
            will generate a file named `foo.{extension_fragment}.swift`.
        proto_source_root: the source root for the `.proto` files
            `generated_files` are generated from.
        generated_files: A list of generated `.swift` files, one of which will
            be used to extract the directory path.

    Returns:
        The repository-relative path to the directory where the `.swift` files
        are being generated.
    """
    if not generated_files:
        return None

    first_path = generated_files[0].path
    dir_name = _generated_file_path(name, extension_fragment, proto_source_root)
    offset = first_path.find(dir_name)
    return first_path[:offset + len(dir_name)]

def register_module_mapping_write_action(name, actions, module_mappings):
    """Registers an action that generates a module mapping for a proto library.

    Args:
        name: The name of the target being analyzed.
        actions: The context's actions object.
        module_mappings: The sequence of module mapping `struct`s to be rendered.
            This sequence should already have duplicates removed.

    Returns:
        The `File` representing the module mapping that will be generated in
        protobuf text format.
    """
    mapping_file = actions.declare_file(
        "{}.protoc_gen_swift_modules.asciipb".format(name),
    )
    content = "".join([_render_text_module_mapping(m) for m in module_mappings])

    actions.write(
        content = content,
        output = mapping_file,
    )

    return mapping_file

def proto_import_path(f, proto_source_root):
    """ Returns the import path of a `.proto` file given its path.

    Args:
        f: The `File` object representing the `.proto` file.
        proto_source_root: The source root for the `.proto` file.

    Returns:
        The path the `.proto` file should be imported at.
    """

    if proto_source_root:
        # Don't want to accidentally match "foo" to "foobar", so add the slash.
        if not proto_source_root.endswith("/"):
            proto_source_root += "/"
        if f.path.startswith(proto_source_root):
            return f.path[len(proto_source_root):]

    # Cross-repository proto file references is sorta a grey area. If that is
    # needed, please see the comments in ProtoCompileActionBuilder.java's
    # guessProtoPathUnderRoot() for some guidance of what would be needed, but
    # the current (Q3/2020) reading says that seems to not maintain the
    # references, so the proto file namespace is likely flat across
    # repositories.
    workspace_path = paths.join(f.root.path, f.owner.workspace_root)
    return paths.relativize(f.path, workspace_path)

def _generated_file_path(
        name,
        extension_fragment,
        proto_source_root,
        proto_file = None):
    """Returns the short path of a generated `.swift` file from a `.proto` file.

    The returned workspace-relative path should be used to declare output files
    so that they are generated relative to the target's package in the output
    directory tree.

    If `proto_file` is `None` (or unspecified), then this function returns the
    workspace-relative path to the directory where the `.swift` files would be
    generated.

    Args:
        name: The name of the target currently being analyzed.
        extension_fragment: An extension fragment that precedes `.swift` on the
            end of the generated files. In other words, the file `foo.proto`
            will generate a file named `foo.{extension_fragment}.swift`.
        proto_source_root: The source root for the `.proto` file.
        proto_file: The `.proto` file whose generated `.swift` path should be
            computed.

    Returns:
        The workspace-relative path of the `.swift` file that will be generated
        for the given `.proto` file, or the workspace-relative path to the
        directory that contains the declared `.swift` files if `proto_file` is
        `None`.
    """
    dir_path = "{name}.protoc_gen_{extension}_swift".format(
        name = name,
        extension = extension_fragment,
    )
    if proto_file:
        generated_file_path = paths.replace_extension(
            proto_import_path(proto_file, proto_source_root),
            ".{}.swift".format(extension_fragment),
        )
        return paths.join(dir_path, generated_file_path)
    return dir_path

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

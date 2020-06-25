# Copyright 2020 The Bazel Authors. All rights reserved.
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

"""Logic for generating Clang module map files."""

load("@bazel_skylib//lib:paths.bzl", "paths")

def write_module_map(
        actions,
        module_map_file,
        module_name,
        dependent_module_names = [],
        public_headers = [],
        public_textual_headers = [],
        private_headers = [],
        private_textual_headers = [],
        workspace_relative = False):
    """Writes the content of the module map to a file.

    Args:
        actions: The actions object from the aspect context.
        module_map_file: A `File` representing the module map being written.
        module_name: The name of the module being generated.
        dependent_module_names: A `list` of names of Clang modules that are
            direct dependencies of the target whose module map is being written.
        public_headers: The `list` of `File`s representing the public modular
            headers of the target whose module map is being written.
        public_textual_headers: The `list` of `File`s representing the public
            textual headers of the target whose module map is being written.
        private_headers: The `list` of `File`s representing the private modular
            headers of the target whose module map is being written.
        private_textual_headers: The `list` of `File`s representing the private
            textual headers of the target whose module map is being written.
        workspace_relative: A Boolean value indicating whether the header paths
            written in the module map file should be relative to the workspace
            or relative to the module map file.
    """
    content = 'module "{}" {{\n'.format(module_name)
    content += "    export *\n\n"

    content += "".join([
        '    header "{}"\n'.format(_header_path(
            header_file = header_file,
            module_map_file = module_map_file,
            workspace_relative = workspace_relative,
        ))
        for header_file in public_headers
    ])
    content += "".join([
        '    private header "{}"\n'.format(_header_path(
            header_file = header_file,
            module_map_file = module_map_file,
            workspace_relative = workspace_relative,
        ))
        for header_file in private_headers
    ])
    content += "".join([
        '    textual header "{}"\n'.format(_header_path(
            header_file = header_file,
            module_map_file = module_map_file,
            workspace_relative = workspace_relative,
        ))
        for header_file in public_textual_headers
    ])
    content += "".join([
        '    private textual header "{}"\n'.format(_header_path(
            header_file = header_file,
            module_map_file = module_map_file,
            workspace_relative = workspace_relative,
        ))
        for header_file in private_textual_headers
    ])

    content += "".join([
        '    use "{}"\n'.format(name)
        for name in dependent_module_names
    ])

    content += "}\n"

    actions.write(
        content = content,
        output = module_map_file,
    )

def _header_path(header_file, module_map_file, workspace_relative):
    """Returns the path to a header file to be written in the module map.

    Args:
        header_file: A `File` representing the header whose path should be
            returned.
        module_map_file: A `File` representing the module map being written,
            which is used during path relativization if necessary.
        workspace_relative: A Boolean value indicating whether the path should
            be workspace-relative or module-map-relative.

    Returns:
        The path to the header file, relative to either the workspace or the
        module map as requested.
    """

    # If the module map is workspace-relative, then the file's path is what we
    # want.
    if workspace_relative:
        return header_file.path

    # Otherwise, since the module map is generated, we need to get the full path
    # to it rather than just its short path (that is, the path starting with
    # bazel-out/). Then, we can simply walk up the same number of parent
    # directories as there are path segments, and append the header file's path
    # to that.
    num_segments = len(paths.dirname(module_map_file.path).split("/"))
    return ("../" * num_segments) + header_file.path

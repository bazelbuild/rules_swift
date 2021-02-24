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

"""Logic for using explicit swiftmodules."""

load("@bazel_skylib//lib:types.bzl", "types")

def write_explicit_swiftmodule_map(
        actions,
        modules,
        explicit_swiftmodule_map_file):
    """Generates an explicit swiftmodule map and writes it to a file.

    Args:
        actions: The object used to register actions.
        modules: The `list` of modules, as returned by
            `swift_common.create_module()` for each swiftmodule to include in
            the map.
        explicit_swiftmodule_map_file: A `File` representing the map to be
            written.
    """
    swiftmodules_map = [
        {
            "moduleName": module.name,
            # Path can be a string when referencing a system module
            "modulePath": module.swift.swiftmodule if types.is_string(module.swift.swiftmodule) else module.swift.swiftmodule.path,
            # TODO: set correctly
            "isFramework": False,
        }
        for module in modules
    ]

    actions.write(
        content = json.encode(swiftmodules_map),
        output = explicit_swiftmodule_map_file,
    )

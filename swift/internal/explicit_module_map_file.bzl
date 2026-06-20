# Copyright 2022 The Bazel Authors. All rights reserved.
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

"""Generates the JSON manifest used to pass Swift modules to the compiler."""

load("@bazel_skylib//lib:paths.bzl", "paths")

def write_explicit_swift_module_map_file(
        *,
        actions,
        explicit_swift_module_map_file,
        module_contexts):
    """Generates the JSON-formatted explicit module map file.

    This file is a manifest that contains the path information for all the
    Swift modules from dependencies that are needed to compile a particular
    module.

    Args:
        actions: The object used to register actions.
        explicit_swift_module_map_file: A `File` to which the generated JSON
            will be written.
        module_contexts: A list of module contexts that provide the Swift
            dependencies for the compilation.
    """

    # If a module has a clang + swift half, they are separate entries in the json file
    module_descriptions = {}
    for module_context in module_contexts:
        base_description = {
            "isFramework": module_context.is_framework,
            "isSystem": module_context.is_system,
            "moduleName": module_context.name,
        }

        if module_context.swift and module_context.swift.swiftmodule:
            if type(module_context.swift.swiftmodule) == "File":
                swiftmodule_path = module_context.swift.swiftmodule.path
            else:
                swiftmodule_path = module_context.swift.swiftmodule
            module_descriptions["swift:{}".format(module_context.name)] = base_description | {
                "modulePath": swiftmodule_path,
            }

        if module_context.clang:
            clang_description = {}
            clang_context = module_context.clang
            if clang_context.module_map:
                # If path is not an attribute of `module_map`, then `module_map` is a string and we use it as our path.
                path = getattr(clang_context.module_map, "path", clang_context.module_map)
                if path and paths.is_absolute(path):
                    fail("clang module map paths must be relative to the execroot, but got an absolute path: {}".format(path))
                clang_description["clangModuleMapPath"] = path
            if clang_context.precompiled_module:
                clang_description["clangModulePath"] = clang_context.precompiled_module.path
            if clang_description:
                module_descriptions["clang:{}".format(module_context.name)] = base_description | clang_description | {"isBridgingHeaderDependency": False}

    actions.write(
        content = json.encode(module_descriptions.values()),
        output = explicit_swift_module_map_file,
    )

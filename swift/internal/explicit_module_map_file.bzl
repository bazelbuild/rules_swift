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
    module_descriptions = {}

    for module_context in module_contexts:
        if module_context.name in module_descriptions:
            # As of Swift 6.2, only one entry per module is permitted.
            continue

        # Set attributes that are applicable to a swift module entry or a
        # clang module entry
        module_description = {
            "moduleName": module_context.name,
            "isFramework": False,
        }
        if module_context.is_system:
            module_description["isSystem"] = module_context.is_system
        if module_context.is_framework:
            module_description["isFramework"] = module_context.is_framework

        # Append a swift moule entry if available
        has_swift_description = False

        if module_context.swift:
            swift_context = module_context.swift
            if swift_context.swiftmodule:
                has_swift_description = True
                module_description["modulePath"] = swift_context.swiftmodule.path

        # Append a clang module entry if available
        has_clang_description = False

        if module_context.clang:
            clang_context = module_context.clang
            if clang_context.module_map:
                # If path is not an attribute of `module_map`, then `module_map` is a string and we use it as our path.
                module_description["clangModuleMapPath"] = getattr(clang_context.module_map, "path", clang_context.module_map)
                has_clang_description = True
            if clang_context.precompiled_module:
                module_description["clangModulePath"] = clang_context.precompiled_module.path
                has_clang_description = True

        if has_swift_description or has_clang_description:
            module_descriptions[module_context.name] = module_description

    actions.write(
        content = json.encode(module_descriptions.values()),
        output = explicit_swift_module_map_file,
    )

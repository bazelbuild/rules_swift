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
    module_descriptions = []

    for module_context in module_contexts:
        if not module_context.swift:
            continue

        swift_context = module_context.swift
        module_description = {
            "moduleName": module_context.name,
            "isFramework": False,
        }
        if swift_context.swiftmodule:
            module_description["modulePath"] = swift_context.swiftmodule.path
        module_descriptions.append(module_description)

    actions.write(
        content = json.encode(module_descriptions),
        output = explicit_swift_module_map_file,
    )

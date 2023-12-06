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

"""Internal APIs used to compute output groups for compilation rules."""

visibility([
    "@build_bazel_rules_swift//swift/...",
])

def supplemental_compilation_output_groups(*supplemental_outputs):
    """Computes output groups from supplemental compilation outputs.

    Args:
        *supplemental_outputs: Zero or more supplemental outputs `struct`s
            returned from calls to `swift_common.compile`.

    Returns:
        A dictionary whose keys are output group names and whose values are
        depsets of `File`s, which is suitable to be `**kwargs`-expanded into an
        `OutputGroupInfo` provider.
    """
    indexstore_files = []
    macro_expansions_files = []
    const_values_files = []

    for outputs in supplemental_outputs:
        if outputs.indexstore_directory:
            indexstore_files.append(outputs.indexstore_directory)
        if outputs.macro_expansion_directory:
            macro_expansions_files.append(outputs.macro_expansion_directory)
        if outputs.const_values_files:
            const_values_files.extend(outputs.const_values_files)

    output_groups = {}
    if indexstore_files:
        output_groups["indexstore"] = depset(indexstore_files)
    if macro_expansions_files:
        output_groups["macro_expansions"] = depset(macro_expansions_files)
    if const_values_files:
        output_groups["const_values"] = depset(const_values_files)
    return output_groups

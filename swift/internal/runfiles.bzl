# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Internal API to generate constants needed by the runfiles library"""

def include_runfiles_constants(label, actions, all_deps):
    """TODO: Do this the right way.

    Args:
        label: The label of the target for which the Swift files are being generated.
        actions: The actions object used to declare the files to be generated and the actions that generate them.
        all_deps: The list of public dependencies of the target.

    Returns:
        A list containing the runfiles constant declared file if applicable;
        otherwise an empty list.
    """
    matches = [dep for dep in all_deps if dep.label == Label("@build_bazel_rules_swift//swift/runfiles:runfiles")]
    if len(matches) > 0:
        repo_name_file = actions.declare_file("Runfiles+Constants.swift")
        actions.write(
            output = repo_name_file,
            content = """
            internal enum BazelRunfilesConstants {{
              static let currentRepository = "{}"
            }}
            """.format(label.workspace_name),
        )
        return [repo_name_file]
    return []

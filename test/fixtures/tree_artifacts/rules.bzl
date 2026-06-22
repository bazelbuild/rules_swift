# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""Rule to generate a tree artifact containing dummy Swift source files."""

visibility("private")

def _generate_swift_tree_artifact_impl(ctx):
    output_dir = ctx.actions.declare_directory(ctx.label.name + ".swift")

    # Simple shell command to write two dummy Swift files into the directory
    ctx.actions.run_shell(
        outputs = [output_dir],
        command = """
        echo 'public struct DummyA {{}}' > {dir}/A.swift
        echo 'public struct DummyB {{}}' > {dir}/B.swift
        """.format(dir = output_dir.path),
        mnemonic = "GenerateSwiftTreeArtifact",
    )

    return [
        DefaultInfo(files = depset([output_dir])),
    ]

generate_swift_tree_artifact = rule(
    implementation = _generate_swift_tree_artifact_impl,
    doc = "Generates a tree artifact containing dummy Swift source files.",
)

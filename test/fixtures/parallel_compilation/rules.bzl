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

"""Helper rules for parallel compilation test fixtures."""

load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftInfo",
    "create_swift_module_context",
)

visibility("private")

def _generate_swift_sources_impl(ctx):
    outputs = []
    commands = []
    for i in range(1, ctx.attr.count + 1):
        out = ctx.actions.declare_file("{}_File{}.swift".format(ctx.label.name, i))
        outputs.append(out)
        commands.append("echo 'public struct Dummy{} {{}}' > {}".format(i, out.path))

    ctx.actions.run_shell(
        outputs = outputs,
        command = "\n".join(commands),
        mnemonic = "GenerateSwiftSources",
    )

    return [
        DefaultInfo(files = depset(outputs)),
    ]

generate_swift_sources = rule(
    implementation = _generate_swift_sources_impl,
    attrs = {
        "count": attr.int(
            doc = "The number of Swift source files to generate.",
            mandatory = True,
        ),
    },
    doc = "Generates a specified number of dummy Swift source files.",
)

def _const_gather_dep_impl(ctx):
    return [
        SwiftInfo(
            modules = [
                create_swift_module_context(
                    name = ctx.label.name,
                    const_gather_protocols = ctx.attr.const_gather_protocols,
                ),
            ],
        ),
    ]

const_gather_dep = rule(
    implementation = _const_gather_dep_impl,
    attrs = {
        "const_gather_protocols": attr.string_list(
            doc = "Protocol names for constant value extraction.",
            mandatory = True,
        ),
    },
    doc = "Propagates a SwiftInfo with const_gather_protocols for testing constant value extraction.",
    provides = [SwiftInfo],
)

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

"""A rule to collect the outputs of a `swift_library`.

This rule is used in tests to simulate "pre-built" artifacts without having to
check them in directly.
"""

load(
    "@build_bazel_rules_swift//swift:swift.bzl",
    "SwiftInfo",
)

def _swiftinterface_transition_impl(_settings, attr):
    # If the `.swiftinterface` file is requested, apply the setting that causes
    # the rule to generate it.
    return {
        "@build_bazel_rules_swift//swift:emit_swiftinterface": attr.swiftinterface != None,
    }

_swiftinterface_transition = transition(
    implementation = _swiftinterface_transition_impl,
    inputs = [],
    outputs = ["@build_bazel_rules_swift//swift:emit_swiftinterface"],
)

def _copy_file(actions, source, destination):
    """Copies the source file to the destination file.

    Args:
        actions: The object used to register actions.
        source: A `File` representing the file to be copied.
        destination: A `File` representing the destination of the copy.
    """
    args = actions.args()
    args.add(source)
    args.add(destination)

    actions.run_shell(
        arguments = [args],
        command = """\
set -e
mkdir -p "$(dirname "$2")"
cp "$1" "$2"
""",
        inputs = [source],
        outputs = [destination],
    )

def _swift_library_artifact_collector_impl(ctx):
    target = ctx.attr.target[0]
    swift_info = target[SwiftInfo]

    if ctx.outputs.static_library:
        linker_inputs = target[CcInfo].linking_context.linker_inputs.to_list()
        lib_to_link = linker_inputs[0].libraries[0]
        _copy_file(
            ctx.actions,
            # based on build config one (but not both) of these will be present
            source = lib_to_link.static_library or lib_to_link.pic_static_library,
            destination = ctx.outputs.static_library,
        )
    if ctx.outputs.swiftdoc:
        _copy_file(
            ctx.actions,
            source = swift_info.direct_modules[0].swift.swiftdoc,
            destination = ctx.outputs.swiftdoc,
        )
    if ctx.outputs.swiftinterface:
        _copy_file(
            ctx.actions,
            source = swift_info.direct_modules[0].swift.swiftinterface,
            destination = ctx.outputs.swiftinterface,
        )
    if ctx.outputs.swiftmodule:
        _copy_file(
            ctx.actions,
            source = swift_info.direct_modules[0].swift.swiftmodule,
            destination = ctx.outputs.swiftmodule,
        )
    return []

swift_library_artifact_collector = rule(
    attrs = {
        "static_library": attr.output(mandatory = False),
        "swiftdoc": attr.output(mandatory = False),
        "swiftinterface": attr.output(mandatory = False),
        "swiftmodule": attr.output(mandatory = False),
        "target": attr.label(
            cfg = _swiftinterface_transition,
            providers = [[CcInfo, SwiftInfo]],
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    implementation = _swift_library_artifact_collector_impl,
)

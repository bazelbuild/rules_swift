# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""Implementation of the `swift_synthesize_interface_aspect` aspect."""

load(
    "//swift/internal:features.bzl",
    "configure_features",
)
load(
    "//swift/internal:interface_synthesizing.bzl",
    "synthesize_interface",
)
load(
    "//swift/internal:toolchain_utils.bzl",
    "get_swift_toolchain",
    "use_swift_toolchain",
)
load(":providers.bzl", "SwiftInfo", "SwiftSynthesizedInterfaceInfo")
load(":swift_clang_module_aspect.bzl", "swift_clang_module_aspect")

visibility("public")

def _get_swift_info(target):
    """Returns the SwiftInfo provider or None if it is not present."""
    if SwiftInfo in target:
        return target[SwiftInfo]
    else:
        return None

def _swift_synthesize_interface_aspect_impl(target, aspect_ctx):
    direct_outputs = []
    synthesized_modules = []

    swift_info = _get_swift_info(target)
    if swift_info and swift_info.direct_modules:
        swift_toolchain = get_swift_toolchain(aspect_ctx)
        feature_configuration = configure_features(
            ctx = aspect_ctx,
            swift_toolchain = swift_toolchain,
            requested_features = aspect_ctx.features,
            unsupported_features = aspect_ctx.disabled_features,
        )

        if CcInfo in target:
            compilation_context = target[CcInfo].compilation_context
        else:
            compilation_context = cc_common.create_compilation_context()

        for module in swift_info.direct_modules:
            output_file = aspect_ctx.actions.declare_file(
                "{}.synthesized_interfaces/{}.synthesized.swift".format(
                    target.label.name,
                    module.name,
                ),
            )
            direct_outputs.append(output_file)
            synthesize_interface(
                actions = aspect_ctx.actions,
                compilation_contexts = [compilation_context],
                feature_configuration = feature_configuration,
                module_name = module.name,
                output_file = output_file,
                swift_infos = [swift_info],
                swift_toolchain = swift_toolchain,
            )
            synthesized_modules.append(
                struct(
                    module_name = module.name,
                    synthesized_interface = output_file,
                ),
            )

    transitive_synthesized_modules = []
    for dep in getattr(aspect_ctx.rule.attr, "deps", []):
        if SwiftSynthesizedInterfaceInfo in dep:
            synth_info = dep[SwiftSynthesizedInterfaceInfo]
            transitive_synthesized_modules.append(
                synth_info.transitive_modules,
            )

    return [
        OutputGroupInfo(
            swift_synthesized_interface = depset(direct_outputs),
        ),
        SwiftSynthesizedInterfaceInfo(
            direct_modules = synthesized_modules,
            transitive_modules = depset(
                synthesized_modules,
                transitive = transitive_synthesized_modules,
            ),
        ),
    ]

swift_synthesize_interface_aspect = aspect(
    attr_aspects = ["deps"],
    doc = """\
        Synthesizes the Swift interface for the target to which it is applied.

        This aspect invokes `swift-synthesize-interface` on the target to which
        it is applied and produces the output in a file located at
        `bazel-bin/<package_name>/<target_name>.synthesized.swift`. This output
        file can be obtained by requesting the output group named
        `swift_synthesized_interface` during the build.

        The output group only contains the synthesized interface for the target
        to which the aspect is *directly* applied; it does not contain the
        synthesized interfaces for any transitive dependencies. If the full
        transitive closure of synthesized interfaces is needed, then clients
        should read the `SwiftSynthesizedInterfaceInfo` provider, which contains
        a `depset` with the full transitive closure.
        """,
    fragments = ["cpp"],
    implementation = _swift_synthesize_interface_aspect_impl,
    provides = [SwiftSynthesizedInterfaceInfo],
    requires = [swift_clang_module_aspect],
    toolchains = use_swift_toolchain(),
)

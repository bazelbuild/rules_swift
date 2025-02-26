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

"""A rule to collect the outputs of `swift_synthesize_interface_aspect`."""

load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftSynthesizedInterfaceInfo",
)
load(
    "@build_bazel_rules_swift//swift:swift_synthesize_interface_aspect.bzl",
    "swift_synthesize_interface_aspect",
)

visibility([
    "@build_bazel_rules_swift//test/...",
])

def _synthesize_interface_applier_impl(ctx):
    target = ctx.attr.target
    info = target[SwiftSynthesizedInterfaceInfo]
    return [DefaultInfo(
        files = depset([
            module.synthesized_interface
            for module in info.direct_modules
        ]),
    )]

synthesize_interface_applier = rule(
    attrs = {
        "target": attr.label(aspects = [swift_synthesize_interface_aspect]),
    },
    implementation = _synthesize_interface_applier_impl,
)

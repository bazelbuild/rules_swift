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

"""Aggregate multiple clang and Swift system modules."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:providers.bzl", "SwiftInfo", "create_swift_module_context")
load(":system_module_transition.bzl", "sdk_min_os_transition", "sdk_min_os_transition_attrs")
load(":utils.bzl", "get_providers")

def _inferred_module_name(ctx):
    target_name = ctx.label.name
    sdk_name = ctx.attr.sdk_name
    if sdk_name:
        prefix = sdk_name + "_"
        if target_name.startswith(prefix):
            return target_name[len(prefix):]
    return target_name

def _system_module_group_impl(ctx):
    modules = []
    if ctx.attr.creates_module:
        modules.append(create_swift_module_context(
            name = _inferred_module_name(ctx),
            is_system = True,
        ))

    return [
        DefaultInfo(),
        cc_common.merge_cc_infos(
            cc_infos = [d[CcInfo] for d in ctx.attr.modules if CcInfo in d],
        ),
        SwiftInfo(
            modules = modules,
            swift_infos = get_providers(ctx.attr.modules, SwiftInfo),
        ),
    ]

system_module_group = rule(
    attrs = sdk_min_os_transition_attrs() | {
        "creates_module": attr.bool(
            default = True,
            doc = "Whether this group propagates a direct system module inferred from the target name.",
        ),
        "modules": attr.label_list(providers = [[CcInfo, SwiftInfo]]),
    },
    cfg = sdk_min_os_transition,
    doc = """\
Aggregates `system_clang_module` (and other `system_module_group`) targets,
merging their `CcInfo` and `SwiftInfo` providers. Uses a `modules` attribute
(not `deps`) so the standard Swift `swift_clang_module_aspect`, which
traverses `deps`, doesn't recurse into the SDK module graph and explode the
`SwiftInfo` it propagates.
""",
    implementation = _system_module_group_impl,
)

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
load("//swift:providers.bzl", "SwiftInfo")
load(":system_module_transition.bzl", "zero_min_os_transition")
load(":utils.bzl", "get_providers")

def _system_module_group_impl(ctx):
    return [
        DefaultInfo(),
        cc_common.merge_cc_infos(
            cc_infos = [d[CcInfo] for d in ctx.attr.modules if CcInfo in d],
        ),
        SwiftInfo(swift_infos = get_providers(ctx.attr.modules, SwiftInfo)),
    ]

system_module_group = rule(
    attrs = {
        "modules": attr.label_list(providers = [[CcInfo, SwiftInfo]]),
    },
    cfg = zero_min_os_transition,
    doc = """\
Aggregates `system_clang_module` (and other `system_module_group`) targets,
merging their `CcInfo` and `SwiftInfo` providers. Uses a `modules` attribute
(not `deps`) so the standard Swift `swift_clang_module_aspect`, which
traverses `deps`, doesn't recurse into the SDK module graph and explode the
`SwiftInfo` it propagates.
""",
    implementation = _system_module_group_impl,
)

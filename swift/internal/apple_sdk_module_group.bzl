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

"""Aggregate multiple clang and Swift modules from the SDK."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:providers.bzl", "SwiftInfo")
load(":utils.bzl", "get_providers")

def _apple_sdk_module_group_impl(ctx):
    return [
        DefaultInfo(),
        cc_common.merge_cc_infos(
            cc_infos = [d[CcInfo] for d in ctx.attr.deps if CcInfo in d],
        ),
        SwiftInfo(swift_infos = get_providers(ctx.attr.deps, SwiftInfo)),
    ]

apple_sdk_module_group = rule(
    attrs = {
        "deps": attr.label_list(providers = [[CcInfo, SwiftInfo]]),
    },
    doc = """\
Aggregates `apple_sdk_clang_module` (and other `apple_sdk_module_group`)
targets, merging their `CcInfo` and `SwiftInfo` providers without attaching
`swift_clang_module_aspect` to the dependencies to avoid circular dependencies.
""",
    implementation = _apple_sdk_module_group_impl,
)

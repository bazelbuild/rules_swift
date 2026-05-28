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

"""Propagate a system SDK prebuilt swiftmodule."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:providers.bzl", "SwiftInfo", "create_swift_module_context", "create_swift_module_inputs")
load(":system_module_transition.bzl", "sdk_min_os_transition", "sdk_min_os_transition_attrs")
load(":utils.bzl", "get_providers")

def _system_swiftmodule_impl(ctx):
    module_context = create_swift_module_context(
        name = ctx.attr.module_name,
        is_framework = ctx.attr.is_framework,
        is_system = True,
        swift = create_swift_module_inputs(
            swiftdoc = None,
            swiftinterface = None,
            swiftmodule = ctx.attr.swiftmodule,
        ),
    )

    return [
        DefaultInfo(),
        cc_common.merge_cc_infos(
            cc_infos = [d[CcInfo] for d in ctx.attr.modules if CcInfo in d],
        ),
        SwiftInfo(
            modules = [module_context],
            swift_infos = get_providers(ctx.attr.modules, SwiftInfo),
        ),
    ]

system_swiftmodule = rule(
    attrs = sdk_min_os_transition_attrs() | {
        "is_framework": attr.bool(
            default = False,
            doc = "Whether the prebuilt Swift module represents a framework module.",
        ),
        "module_name": attr.string(
            doc = "The name of the Swift module represented by this target.",
            mandatory = True,
        ),
        "modules": attr.label_list(
            allow_empty = True,
            doc = """\
A list of system modules that this Swift module depends on. Named `modules`
instead of `deps` so the standard Swift `swift_clang_module_aspect` doesn't
recurse into the SDK module graph from consumers.
""",
            mandatory = False,
            providers = [[CcInfo, SwiftInfo]],
        ),
        "swiftmodule": attr.string(
            doc = """\
The path to a system-provided prebuilt Swift module.

Variables `__BAZEL_XCODE_SDKROOT__` and `__BAZEL_XCODE_DEVELOPER_DIR__` will be
substituted.
""",
            mandatory = True,
        ),
    },
    cfg = sdk_min_os_transition,
    doc = """\
Propagates an Xcode-provided prebuilt `.swiftmodule` for a system module.
""",
    implementation = _system_swiftmodule_impl,
)

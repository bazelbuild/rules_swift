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

"""Surface a prebuilt SDK `.swiftmodule` directly without recompiling."""

load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo", "create_swift_module_context", "create_swift_module_inputs")
load("@build_bazel_rules_swift//swift/internal:system_module_transition.bzl", "sdk_min_os_transition", "sdk_min_os_transition_attrs")
load("@build_bazel_rules_swift//swift/internal:utils.bzl", "get_providers")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _system_swiftmodule_impl(ctx):
    deps = ctx.attr.modules
    swift_infos = get_providers(deps, SwiftInfo)
    cc_info = cc_common.merge_cc_infos(cc_infos = [
        dep[CcInfo]
        for dep in deps
        if CcInfo in dep
    ])

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
        SwiftInfo(
            modules = [module_context],
            swift_infos = swift_infos,
        ),
        cc_info,
    ]

system_swiftmodule = rule(
    cfg = sdk_min_os_transition,
    attrs = sdk_min_os_transition_attrs() | {
        "is_framework": attr.bool(
            default = False,
            doc = "Whether the prebuilt swiftmodule represents a framework module.",
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
Path to the prebuilt `.swiftmodule` file shipped by the toolchain (typically
under `<toolchain>/usr/lib/swift/<platform>/prebuilt-modules/<sdk-version>/`).
The string flows directly into the consumer's explicit Swift module map as
the `modulePath`; the worker substitutes `__BAZEL_XCODE_SDKROOT__` and
`__BAZEL_XCODE_DEVELOPER_DIR__` placeholders in the JSON map at action time
so swiftc can open the SDK file without Bazel staging it as an input.
""",
            mandatory = True,
        ),
    },
    doc = """\
Surfaces a prebuilt SDK `.swiftmodule` so consumers can reference it via the
explicit Swift module map without paying a per-target interface compile. The
path is treated like `system_swiftinterface`'s interface path: a placeholder
string resolved at action time, not a Bazel-tracked input.
""",
    implementation = _system_swiftmodule_impl,
)

# Copyright 2019 The Bazel Authors. All rights reserved.
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

"""Common build definitions used by test fixtures."""

load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo")
load(
    "@build_bazel_rules_swift//swift:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)
load(
    "@build_bazel_rules_swift//swift:swift_interop_info.bzl",
    "create_swift_interop_info",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

visibility([
    "@build_bazel_rules_swift//test/fixtures/...",
])

# Common tags that prevent the test fixtures from actually being built (i.e.,
# their actions executed) when running `bazel test` to do analysis testing.
FIXTURE_TAGS = [
    "manual",
    "notap",
]

def _forward_swift_info_from_swift_clang_module_aspect_impl(ctx):
    if SwiftInfo in ctx.attr.target:
        return [ctx.attr.target[SwiftInfo]]
    return []

forward_swift_info_from_swift_clang_module_aspect = rule(
    attrs = {
        "target": attr.label(
            aspects = [swift_clang_module_aspect],
            mandatory = True,
        ),
    },
    doc = """\
Applies `swift_clang_module_aspect` to the given target and forwards the
`SwiftInfo` provider that it attaches to the target, if any.
""",
    implementation = _forward_swift_info_from_swift_clang_module_aspect_impl,
)

def _reexport_swift_info_impl(ctx):
    return [
        SwiftInfo(
            direct_swift_infos = [
                dep[SwiftInfo]
                for dep in ctx.attr.deps
                if SwiftInfo in dep
            ],
        ),
    ]

reexport_swift_info = rule(
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            providers = [SwiftInfo],
        ),
    },
    doc = """\
Forwards the `SwiftInfo` providers of its dependencies as `direct_swift_infos`,
re-exporting their `direct_modules`.
""",
    implementation = _reexport_swift_info_impl,
)

def _reexport_swift_interop_info_impl(ctx):
    if ctx.files.hdrs:
        compilation_context = cc_common.create_compilation_context(
            headers = depset(ctx.files.hdrs),
        )
    else:
        compilation_context = None
    return [
        create_swift_interop_info(
            compilation_context = compilation_context,
            direct_swift_infos = [
                dep[SwiftInfo]
                for dep in ctx.attr.deps
                if SwiftInfo in dep
            ],
        ),
    ]

reexport_swift_interop_info = rule(
    attrs = {
        "deps": attr.label_list(
            providers = [SwiftInfo],
        ),
        "hdrs": attr.label_list(
            allow_files = True,
        ),
    },
    doc = """\
Propagates a `SwiftInteropInfo` provider with optional `hdrs` in its compilation
context and the `SwiftInfo` providers of `deps` in `direct_swift_infos`.
""",
    implementation = _reexport_swift_interop_info_impl,
)

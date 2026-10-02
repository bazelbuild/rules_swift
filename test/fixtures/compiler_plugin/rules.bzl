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

"""Helper rules for compiler plugin tests."""

load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo")

visibility("private")

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
re-exporting their `direct_modules` (including any associated compiler plugins).
""",
    implementation = _reexport_swift_info_impl,
)

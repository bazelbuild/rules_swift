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

"""Implementation of the `swift_cross_import_overlays_group` rule."""

load(
    "//swift/internal:providers.bzl",
    "SwiftCrossImportOverlayInfo",
    "SwiftCrossImportOverlaysGroupInfo",
)

def _swift_cross_import_overlays_group_impl(ctx):
    return [
        SwiftCrossImportOverlaysGroupInfo(
            overlays = [t[SwiftCrossImportOverlayInfo] for t in ctx.attr.overlays],
        ),
    ]

swift_cross_import_overlays_group = rule(
    attrs = {
        "overlays": attr.label_list(
            allow_empty = True,
            doc = """\
A list of `swift_cross_import_overlay` targets to aggregate. May be a `select`
so that platform-specific overlays can be folded into a single label.
""",
            providers = [[SwiftCrossImportOverlayInfo]],
        ),
    },
    doc = """\
Aggregates many `swift_cross_import_overlay` targets into one provider that can
be passed via a single toolchain attribute.
""",
    implementation = _swift_cross_import_overlays_group_impl,
)

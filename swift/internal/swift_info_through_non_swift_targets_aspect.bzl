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

"""Propagates `SwiftInfo` providers for non-Swift targets with Swift dependencies."""

load(":api.bzl", "swift_common")
load(":providers.bzl", "SwiftInfo")

def _swift_info_through_non_swift_targets_aspect_impl(target, aspect_ctx):
    # Do nothing if the target already propagates `SwiftInfo`.
    if SwiftInfo in target:
        return []

    # If there aren't any deps that propagate `SwiftInfo`, do nothing; we don't want to propagate
    # an empty one.
    deps = getattr(aspect_ctx.rule.attr, "deps", [])
    swift_deps = [dep for dep in deps if SwiftInfo in dep]
    if not swift_deps:
        return []

    return [swift_common.merge_swift_infos(
        [dep[SwiftInfo] for dep in swift_deps if SwiftInfo in dep],
    )]

swift_info_through_non_swift_targets_aspect = aspect(
    attr_aspects = ["deps"],
    doc = """
Ensures that `SwiftInfo` providers are propagated through non-Swift targets in the build graph.

When a `swift_library` depends on a non-Swift target like an `objc_library` or `cc_library`,
those targets don't know about the `SwiftInfo` provider and do not propagate it. When this
happens, the `swift_library` targets further up in the build graph will not have all of the
`.swiftmodule` files that they need to properly import dependencies.

This aspect fixes this problem by ensuring that non-Swift targets also propagate the merged
`SwiftInfo`s of their dependencies.

This aspect is an implementation detail of the Swift build rules and is not meant to be attached
to other rules or run independently.
""",
    implementation = _swift_info_through_non_swift_targets_aspect_impl,
)

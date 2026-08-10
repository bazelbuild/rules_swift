# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Helper functions for users of Swift overlays."""

load(
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    "SwiftOverlayCompileInfo",
)

visibility("public")

SwiftOverlayTargetInfo = provider(
    doc = """\
An empty marker provider used to identify `swift_overlay` targets.

NOTE: This provider only exists to support the new requirement that aspects
only visit aspect hints that list one of the hinted target's providers in their
`required_aspect_hints_providers` attribute, because we do not want to leak an
internal provider that contains more information for this purpose. We are
hopeful that improvements to that API will make this provider obsolete.
""",
    fields = {},
)

def is_swift_overlay(target):
    """Returns a value indicating whether the given target is a `swift_overlay`.

    This is meant to be used by aspects that visit the `aspect_hints` of a
    target to identify the `swift_overlay` target (if present) without making
    the provider public or requiring those aspects to propagate the information
    themselves.

    Args:
        target: A `Target`; for example, an element of
            `ctx.rule.attr.aspect_hints` accessed inside an aspect.

    Returns:
        True if the target is a `swift_overlay`, otherwise False.
    """
    return SwiftOverlayCompileInfo in target

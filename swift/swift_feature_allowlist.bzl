# Copyright 2021 The Bazel Authors. All rights reserved.
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

"""Support for restricting access to features based on an allowlist."""

load("//swift/internal:package_specs.bzl", "parse_package_specs")
load(":providers.bzl", "SwiftFeatureAllowlistInfo")

def _swift_feature_allowlist_impl(ctx):
    return [SwiftFeatureAllowlistInfo(
        allowlist_label = str(ctx.label),
        managed_features = ctx.attr.managed_features,
        package_specs = parse_package_specs(
            package_specs = ctx.attr.packages,
            workspace_name = ctx.label.workspace_name,
        ),
    )]

swift_feature_allowlist = rule(
    attrs = {
        "managed_features": attr.string_list(
            allow_empty = True,
            doc = """\
A list of feature strings that are permitted to be specified by the targets in
the packages matched by the `packages` attribute. This list may include both
feature names and/or negations (a name with a leading `-`); a regular feature
name means that the targets in the matching packages may explicitly request that
the feature be enabled, and a negated feature means that the target may
explicitly request that the feature be disabled.

For example, `managed_features = ["foo", "-bar"]` means that targets in the
allowlist's packages may request that feature `"foo"` be enabled and that
feature `"bar"` be disabled.
""",
            mandatory = False,
        ),
        "packages": attr.string_list(
            allow_empty = True,
            doc = """\
A list of strings representing packages (possibly recursive) whose targets are
allowed to enable/disable the features in `managed_features`. Each package
pattern is written in the syntax used by the `package_group` function:

*   `//foo/bar`: Targets in the package `//foo/bar` but not in subpackages.
*   `//foo/bar/...`: Targets in the package `//foo/bar` and any of its
    subpackages.
*   A leading `-` excludes packages that would otherwise have been included by
    the patterns in the list.

Exclusions always take priority over inclusions; order in the list is
irrelevant.
""",
            mandatory = True,
        ),
    },
    doc = """\
Limits the ability to request or disable certain features to a set of packages
(and possibly subpackages) in the workspace.

A Swift toolchain target can reference any number (zero or more) of
`swift_feature_allowlist` targets. The features managed by these allowlists may
overlap. For some package _P_, a feature is allowed to be used by targets in
that package if _P_ matches the `packages` patterns in *all* of the allowlists
that manage that feature.

A feature that is not managed by any allowlist is allowed to be used by any
package.
""",
    implementation = _swift_feature_allowlist_impl,
)

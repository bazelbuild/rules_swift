# Copyright 2018 The Bazel Authors. All rights reserved.
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

"""Aspects that handle `cc_libs` and regular `deps` from other C dependencies.

In order to support libraries with mixed C and Swift code (for example, building
Foundation or Dispatch from source, if one is so inclined), the C `.o` files and
the Swift `.o` files must be in the same archive if they refer to symbols across
language boundaries in both directions. We handle this using the `cc_libs`
attribute on `swift_library` and `swift_core_library`, which says that the
direct objects from the `cc_library` targets listed in that attribute should be
merged into the same archive as the `swift_library`. We do not, however, embed
the dependencies of those `cc_library` targets, but we still want them to be
linked into the final binary.

To achieve this, one version of this aspect attaches to the `cc_libs` attribute
and walks the dependency graph to collect the strictly indirect C libraries
while ignoring the libraries that are directly listed in `cc_libs`. Therefore,
the compilation logic will merge the `cc_libs` archives with the `swift_library`
archive and only propagate these indirect C libraries to the linker. The other
aspect, which attaches to `deps`, simply propagates the entire set of transitive
libraries to the depender.
"""

load("@bazel_tools//tools/cpp:legacy_cc_starlark_api_shim.bzl", "get_libs_for_static_executable")
load(":providers.bzl", "SwiftCcLibsInfo")

def _build_providers_for_cc_target(target, aspect_ctx):
    """Builds `SwiftCcLibsInfo` and `objc` providers for a `CcInfo`-propagating target.

    Args:
        target: The `Target` to which the aspect is being applied.
        aspect_ctx: The aspect context.

    Returns:
      The list of providers.
    """
    if aspect_ctx.attr._include_directs:
        all_libraries_set = get_libs_for_static_executable(target)
    else:
        all_libraries = []
        if hasattr(aspect_ctx.rule.attr, "deps"):
            for dep in aspect_ctx.rule.attr.deps:
                if CcInfo in dep:
                    all_libraries.append(get_libs_for_static_executable(dep))
        all_libraries_set = depset(transitive = all_libraries)

    return [SwiftCcLibsInfo(libraries = all_libraries_set)]

def _build_transitive_providers(aspect_ctx):
    """Builds `SwiftCcLibsInfo` and `objc` providers for a non-`CcInfo`-propagating target.

    This ensures that libraries are still propagated transitively through dependency edges between
    `swift_library` targets.

    Args:
        aspect_ctx: The aspect context.

    Returns:
      The list of providers.
    """
    all_libraries = []
    if hasattr(aspect_ctx.rule.attr, "deps"):
        for dep in aspect_ctx.rule.attr.deps:
            if SwiftCcLibsInfo in dep:
                all_libraries.append(dep[SwiftCcLibsInfo].libraries)
    all_libraries_set = depset(transitive = all_libraries)

    return [SwiftCcLibsInfo(libraries = all_libraries_set)]

def _swift_cc_libs_aspect_impl(target, aspect_ctx):
    if CcInfo in target:
        return _build_providers_for_cc_target(target, aspect_ctx)
    else:
        return _build_transitive_providers(aspect_ctx)

# This flavor of the aspect includes direct dependencies, so it is used to
# collect libraries depended on by a `swift_library` via the `deps` attribute.
swift_cc_libs_aspect = aspect(
    attrs = {
        "_include_directs": attr.bool(default = True),
    },
    implementation = _swift_cc_libs_aspect_impl,
)

# This flavor of the aspect excludes direct dependencies, so it is used to
# collect libraries depended on *indirectly* by a `swift_library` via the
# `cc_libs` attribute, but excluding the direct libraries because they will be
# embedded directly in the `swift_library`'s archive.
swift_cc_libs_excluding_directs_aspect = aspect(
    attrs = {
        "_include_directs": attr.bool(default = False),
    },
    implementation = _swift_cc_libs_aspect_impl,
)

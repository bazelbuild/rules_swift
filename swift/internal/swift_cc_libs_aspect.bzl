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

"""Aspect that handles C++ `deps` of Swift targets."""

load(":providers.bzl", "SwiftCcLibsInfo")

def _build_providers_for_cc_target(target, aspect_ctx):
    """Builds a `SwiftCcLibsInfo` provider for a `CcInfo`-propagating target.

    Args:
        target: The `Target` to which the aspect is being applied.
        aspect_ctx: The aspect context.

    Returns:
        The list of providers.
    """
    static_libraries = []
    for library in target[CcInfo].linking_context.libraries_to_link:
        if library.pic_static_library:
            static_libraries.append(library.pic_static_library)
        elif library.static_library:
            static_libraries.append(library.static_library)

    return [SwiftCcLibsInfo(libraries = depset(direct = static_libraries, order = "topological"))]

def _build_transitive_providers(aspect_ctx):
    """Builds a `SwiftCcLibsInfo` provider for a non-`cc`-propagating target.

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
    all_libraries_set = depset(transitive = all_libraries, order = "topological")

    return [SwiftCcLibsInfo(libraries = all_libraries_set)]

def _swift_cc_libs_aspect_impl(target, aspect_ctx):
    if CcInfo in target and not apple_common.Objc in target:
        return _build_providers_for_cc_target(target, aspect_ctx)
    else:
        return _build_transitive_providers(aspect_ctx)

swift_cc_libs_aspect = aspect(
    implementation = _swift_cc_libs_aspect_impl,
)

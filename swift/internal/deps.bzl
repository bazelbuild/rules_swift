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

"""Helper functions for working with dependencies."""

load(":providers.bzl", "SwiftCcLibsInfo", "SwiftInfo")

def collect_link_libraries(target):
    """Returns a list of `depset`s containing the transitive libraries of `target`.

    This function handles the differences between the various providers that we support to provide
    a uniform API for collecting the transitive libraries that must be linked against when building
    a particular target.

    Args:
        target: The target from which the transitive libraries will be collected.

    Returns:
        A list of `depset`s containing the transitive libraries of `target`.
    """
    depsets = []

    if apple_common.Objc in target:
        depsets.append(target[apple_common.Objc].library)

    if SwiftInfo in target:
        depsets.append(target[SwiftInfo].transitive_libraries)

    if SwiftCcLibsInfo in target:
        depsets.append(target[SwiftCcLibsInfo].libraries)
    elif CcInfo in target:
        # TODO(b/124371696): This edge case occurs for the "malloc" target of binaries, which is
        # passed directly to the link action and does not pass through swift_cc_libs_aspect. This
        # can be removed when all linking logic is consolidated into `CcInfo`.
        linking_context = target[CcInfo].linking_context
        for library in linking_context.libraries_to_link:
            if library.pic_static_library:
                depsets.append(depset(direct = [library.pic_static_library]))
            elif library.static_library:
                depsets.append(depset(direct = [library.static_library]))

    return [depset(transitive = depsets, order = "topological")]

def legacy_build_swift_info(
        deps = [],
        direct_additional_inputs = [],
        direct_defines = [],
        direct_libraries = [],
        direct_linkopts = [],
        direct_swiftdocs = [],
        direct_swiftmodules = [],
        module_name = None,
        swift_version = None):
    """Builds a `SwiftInfo` provider from direct outputs and dependencies.

    TODO(b/124371696): This function is still used by `swift_library` and `swift_import` to get the
    correct link library behavior, but it will be removed when linking logic moves entirely to
    `CcInfo`.

    Args:
        deps: A list of dependencies of the target being built, which provide `SwiftInfo` providers.
        direct_additional_inputs: A list of additional input files passed into a library or binary
            target via the `swiftc_inputs` attribute.
        direct_defines: A list of defines that will be provided as `copts` of the target being
            built.
        direct_libraries: A list of `.a` files that are the direct outputs of the target being
            built.
        direct_linkopts: A list of linker flags that will be passed to the linker when the target
            being built is linked into a binary.
        direct_swiftdocs: A list of `.swiftdoc` files that are the direct outputs of the target
            being built.
        direct_swiftmodules: A list of `.swiftmodule` files that are the direct outputs of the
            target being built.
        module_name: A string containing the name of the Swift module, or `None` if the provider
            does not represent a compiled module (this happens, for example, with `proto_library`
            targets that act as "collectors" of other modules but have no sources of their own).
        swift_version: A string containing the value of the `-swift-version` flag used when
            compiling this target, or `None` if it was not set or is not relevant.

    Returns:
        A new `SwiftInfo` provider that propagates the direct and transitive libraries and modules
        for the target being built.
    """
    transitive_additional_inputs = []
    transitive_defines = []
    transitive_libraries = []
    transitive_linkopts = []
    transitive_swiftdocs = []
    transitive_swiftmodules = []

    # Note that we also collect the transitive libraries and linker flags from `cc_library`
    # dependencies and propagate them through the `SwiftInfo` provider; this is necessary because we
    # cannot construct our own `CcSkylarkApiProviders` from within Skylark, but only consume them.
    for dep in deps:
        transitive_libraries.extend(collect_link_libraries(dep))
        if SwiftInfo in dep:
            swift_info = dep[SwiftInfo]
            transitive_additional_inputs.append(swift_info.transitive_additional_inputs)
            transitive_defines.append(swift_info.transitive_defines)
            transitive_linkopts.append(swift_info.transitive_linkopts)
            transitive_swiftdocs.append(swift_info.transitive_swiftdocs)
            transitive_swiftmodules.append(swift_info.transitive_swiftmodules)
        if CcInfo in dep:
            transitive_linkopts.append(
                depset(direct = dep[CcInfo].linking_context.user_link_flags),
            )

    return SwiftInfo(
        direct_defines = direct_defines,
        direct_libraries = direct_libraries,
        direct_linkopts = direct_linkopts,
        direct_swiftdocs = direct_swiftdocs,
        direct_swiftmodules = direct_swiftmodules,
        module_name = module_name,
        swift_version = swift_version,
        transitive_additional_inputs = depset(
            direct = direct_additional_inputs,
            transitive = transitive_additional_inputs,
        ),
        transitive_defines = depset(direct = direct_defines, transitive = transitive_defines),
        transitive_libraries = depset(
            direct = direct_libraries,
            transitive = transitive_libraries,
            order = "topological",
        ),
        transitive_linkopts = depset(direct = direct_linkopts, transitive = transitive_linkopts),
        transitive_swiftdocs = depset(direct = direct_swiftdocs, transitive = transitive_swiftdocs),
        transitive_swiftmodules = depset(
            direct = direct_swiftmodules,
            transitive = transitive_swiftmodules,
        ),
    )

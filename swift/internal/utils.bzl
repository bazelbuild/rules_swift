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

"""Common utility definitions used by various BUILD rules."""

load(":providers.bzl", "SwiftInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")

def collect_cc_libraries(
        cc_info,
        include_dynamic = False,
        include_interface = False,
        include_pic_static = False,
        include_static = False):
    """Returns a list of libraries referenced in the given `CcInfo` provider.

    Args:
        cc_info: The `CcInfo` provider whose libraries should be returned.
        include_dynamic: True if dynamic libraries should be included in the
            list.
        include_interface: True if interface libraries should be included in the
            list.
        include_pic_static: True if PIC static libraries should be included in
            the list. If there is no PIC library, the non-PIC library will be
            used instead.
        include_static: True if non-PIC static libraries should be included in
            the list.

    Returns:
        The list of libraries built or depended on by the given provier.
    """
    libraries = []

    for linker_input in cc_info.linking_context.linker_inputs.to_list():
        for library in linker_input.libraries:
            if include_pic_static:
                if library.pic_static_library:
                    libraries.append(library.pic_static_library)
                elif library.static_library:
                    libraries.append(library.static_library)
            elif include_static and library.static_library:
                libraries.append(library.static_library)

            if include_dynamic and library.dynamic_library:
                libraries.append(library.dynamic_library)
            if include_interface and library.interface_library:
                libraries.append(library.interface_library)

    return libraries

def collect_implicit_deps_providers(targets):
    """Returns a struct with important providers from a list of implicit deps.

    Note that the relationship between each provider in the list and the target
    it originated from is no longer retained.

    Args:
        targets: A list (possibly empty) of `Target`s.

    Returns:
        A `struct` containing three fields:

        *   `cc_infos`: The merged `CcInfo` provider from the given targets.
        *   `objc_infos`: The merged `apple_common.Objc` provider from the given
            targets.
        *   `swift_infos`: The merged `SwiftInfo` provider from the given
            targets.
    """
    cc_infos = []
    objc_infos = []
    swift_infos = []

    for target in targets:
        if CcInfo in target:
            cc_infos.append(target[CcInfo])
        if apple_common.Objc in target:
            objc_infos.append(target[apple_common.Objc])
        if SwiftInfo in target:
            swift_infos.append(target[SwiftInfo])

    return struct(
        cc_infos = cc_infos,
        objc_infos = objc_infos,
        swift_infos = swift_infos,
    )

def compact(sequence):
    """Returns a copy of the sequence with any `None` items removed.

    Args:
        sequence: The sequence of items to compact.

    Returns: A copy of the sequence with any `None` items removed.
    """
    return [item for item in sequence if item != None]

def create_cc_info(
        *,
        cc_infos = [],
        compilation_outputs = None,
        defines = [],
        includes = [],
        linker_inputs = [],
        private_cc_infos = []):
    """Creates a `CcInfo` provider from Swift compilation info and deps.

    Args:
        cc_infos: A list of `CcInfo` providers from public dependencies, whose
            compilation and linking contexts should both be merged into the new
            provider.
        compilation_outputs: The compilation outputs from a Swift compile
            action, as returned by `swift_common.compile`, or None.
        defines: The list of compiler defines to insert into the compilation
            context.
        includes: The list of include paths to insert into the compilation
            context.
        linker_inputs: A list of `LinkerInput` objects that represent the
            libraries that should be linked into the final binary as well as any
            additional inputs and flags that should be passed to the linker.
        private_cc_infos: A list of `CcInfo` providers from private
            (implementation-only) dependencies, whose linking contexts should be
            merged into the new provider but whose compilation contexts should
            be excluded.

    Returns:
        A new `CcInfo`.
    """
    all_headers = []
    if compilation_outputs:
        all_headers = compact([compilation_outputs.generated_header])

    local_cc_infos = [
        CcInfo(
            linking_context = cc_common.create_linking_context(
                linker_inputs = depset(linker_inputs),
            ),
            compilation_context = cc_common.create_compilation_context(
                defines = depset(defines),
                headers = depset(all_headers),
                includes = depset(includes),
            ),
        ),
    ]

    if private_cc_infos:
        # Merge the private deps' CcInfos, but discard the compilation context
        # and only propagate the linking context.
        full_private_cc_info = cc_common.merge_cc_infos(
            cc_infos = private_cc_infos,
        )
        local_cc_infos.append(CcInfo(
            linking_context = full_private_cc_info.linking_context,
        ))

    return cc_common.merge_cc_infos(
        cc_infos = cc_infos,
        direct_cc_infos = local_cc_infos,
    )

def expand_locations(ctx, values, targets = []):
    """Expands the `$(location)` placeholders in each of the given values.

    Args:
        ctx: The rule context.
        values: A list of strings, which may contain `$(location)` placeholders.
        targets: A list of additional targets (other than the calling rule's
            `deps`) that should be searched for substitutable labels.

    Returns:
        A list of strings with any `$(location)` placeholders filled in.
    """
    return [ctx.expand_location(value, targets) for value in values]

def expand_make_variables(ctx, values, attribute_name):
    """Expands all references to Make variables in each of the given values.

    Args:
        ctx: The rule context.
        values: A list of strings, which may contain Make variable placeholders.
        attribute_name: The attribute name string that will be presented in
            console when an error occurs.

    Returns:
        A list of strings with Make variables placeholders filled in.
    """
    return [
        ctx.expand_make_variables(attribute_name, value, {})
        for value in values
    ]

def get_swift_executable_for_toolchain(ctx):
    """Returns the Swift driver executable that the toolchain should use.

    Args:
        ctx: The toolchain's rule context.

    Returns:
        A `File` representing a custom Swift driver executable that the
        toolchain should use if provided by the toolchain target or by a command
        line option, or `None` if the default driver bundled with the toolchain
        should be used.
    """

    # If the toolchain target itself specifies a custom driver, use that.
    swift_executable = getattr(ctx.file, "swift_executable", None)

    # If no custom driver was provided by the target, check the value of the
    # command-line option and use that if it was provided.
    if not swift_executable:
        default_swift_executable_files = getattr(
            ctx.files,
            "_default_swift_executable",
            None,
        )

        if default_swift_executable_files:
            if len(default_swift_executable_files) > 1:
                fail(
                    "The 'default_swift_executable' option must point to a " +
                    "single file, but we found {}".format(
                        str(default_swift_executable_files),
                    ),
                )

            swift_executable = default_swift_executable_files[0]

    return swift_executable

def get_output_groups(targets, group_name):
    """Returns files in an output group from each target in a list.

    The returned list may not be the same size as `targets` if some of the
    targets do not contain the requested output group. This is not an error.

    Args:
        targets: A list of targets.
        group_name: The name of the output group.

    Returns:
        A list of `depset`s of `File`s from the requested output group for each
        target.
    """
    groups = []

    for target in targets:
        group = getattr(target[OutputGroupInfo], group_name, None)
        if group:
            groups.append(group)

    return groups

def get_providers(targets, provider, map_fn = None):
    """Returns the given provider (or a field) from each target in the list.

    The returned list may not be the same size as `targets` if some of the
    targets do not contain the requested provider. This is not an error.

    The main purpose of this function is to make this common operation more
    readable and prevent mistyping the list comprehension.

    Args:
        targets: A list of targets.
        provider: The provider to retrieve.
        map_fn: A function that takes a single argument and returns a single
            value. If this is present, it will be called on each provider in the
            list and the result will be returned in the list returned by
            `get_providers`.

    Returns:
        A list of the providers requested from the targets.
    """
    if map_fn:
        return [
            map_fn(target[provider])
            for target in targets
            if provider in target
        ]
    return [target[provider] for target in targets if provider in target]

def merge_runfiles(all_runfiles):
    """Merges a list of `runfiles` objects.

    Args:
        all_runfiles: A list containing zero or more `runfiles` objects to
            merge.

    Returns:
        A merged `runfiles` object, or `None` if the list was empty.
    """
    result = None
    for runfiles in all_runfiles:
        if result == None:
            result = runfiles
        else:
            result = result.merge(runfiles)
    return result

def owner_relative_path(file):
    """Returns the part of the given file's path relative to its owning package.

    This function has extra logic to properly handle references to files in
    external repositoriies.

    Args:
        file: The file whose owner-relative path should be returned.

    Returns:
        The owner-relative path to the file.
    """
    root = file.owner.workspace_root
    package = file.owner.package

    if file.is_source:
        # Even though the docs say a File's `short_path` doesn't include the
        # root, Bazel special cases anything from an external repository and
        # includes a relative path (`../`) to the file. On the File's `owner` we
        # can get the `workspace_root` to try and line things up, but it is in
        # the form of "external/[name]". However the File's `path` does include
        # the root and leaves it in the "external/" form, so we just relativize
        # based on that instead.
        return paths.relativize(file.path, paths.join(root, package))
    elif root:
        # As above, but for generated files. The same mangling happens in
        # `short_path`, but since it is generated, the `path` includes the extra
        # output directories used by Bazel. So, we pick off the parent directory
        # segment that Bazel adds to the `short_path` and turn it into
        # "external/" so a relative path from the owner can be computed.
        short_path = file.short_path

        # Sanity check.
        if (
            not root.startswith("external/") or
            not short_path.startswith("../")
        ):
            fail(("Generated file in a different workspace with unexpected " +
                  "short_path ({short_path}) and owner.workspace_root " +
                  "({root}).").format(
                root = root,
                short_path = short_path,
            ))

        return paths.relativize(
            paths.join("external", short_path[3:]),
            paths.join(root, package),
        )
    else:
        return paths.relativize(file.short_path, package)

def struct_fields(s):
    """Returns a dictionary containing the fields in the struct `s`.

    Args:
        s: A `struct`.

    Returns:
        The fields in `s` and their values.
    """
    return {
        field: getattr(s, field)
        for field in dir(s)
        # TODO(b/36412967): Remove the `to_json` and `to_proto` checks.
        if field not in ("to_json", "to_proto")
    }

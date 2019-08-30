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

load("@bazel_skylib//lib:paths.bzl", "paths")

def collect_cc_libraries(
        cc_info,
        include_dynamic = False,
        include_interface = False,
        include_pic_static = False,
        include_static = False):
    """Returns a list of link libraries referenced in the given `CcInfo` provider.

    Args:
        cc_info: The `CcInfo` provider whose libraries should be returned.
        include_dynamic: True if dynamic libraries should be included in the list.
        include_interface: True if interface libraries should be included in the list.
        include_pic_static: True if PIC static libraries should be included in the list. If there
            is no PIC library, the non-PIC library will be used instead.
        include_static: True if non-PIC static libraries should be included in the list.

    Returns:
        The list of libraries built or depended on by the given provier.
    """
    libraries = []

    # TODO(https://github.com/bazelbuild/bazel/issues/8118): Remove once flag is flipped
    libraries_to_link = cc_info.linking_context.libraries_to_link
    if hasattr(libraries_to_link, "to_list"):
        libraries_to_link = libraries_to_link.to_list()

    for library in libraries_to_link:
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

def compact(sequence):
    """Returns a copy of the sequence with any `None` items removed.

    Args:
        sequence: The sequence of items to compact.

    Returns: A copy of the sequence with any `None` items removed.
    """
    return [item for item in sequence if item != None]

def create_cc_info(
        additional_inputs = [],
        cc_infos = [],
        compilation_outputs = None,
        libraries_to_link = [],
        user_link_flags = []):
    """Creates a `CcInfo` provider from Swift compilation information and dependencies.

    Args:
        additional_inputs: A list of additional files that should be passed as inputs to the final
            link action.
        cc_infos: A list of `CcInfo` providers from dependencies that should be merged into the
            new provider.
        compilation_outputs: The compilation outputs from a Swift compile action, as returned by
            `swift_common.compile`, or None.
        libraries_to_link: A list of `LibraryToLink` objects that represent the libraries that
            should be linked into the final binary.
        user_link_flags: A list of flags that should be passed to the final link action.

    Returns:
        A new `CcInfo`.
    """
    all_additional_inputs = list(additional_inputs)
    all_user_link_flags = list(user_link_flags)
    if compilation_outputs:
        all_additional_inputs.extend(compilation_outputs.linker_inputs)
        all_user_link_flags.extend(compilation_outputs.linker_flags)

    this_cc_info = CcInfo(
        linking_context = cc_common.create_linking_context(
            additional_inputs = all_additional_inputs,
            libraries_to_link = libraries_to_link,
            user_link_flags = all_user_link_flags,
        ),
    )
    return cc_common.merge_cc_infos(cc_infos = [this_cc_info] + cc_infos)

def expand_locations(ctx, values, targets = []):
    """Expands the `$(location)` placeholders in each of the given values.

    Args:
      ctx: The rule context.
      values: A list of strings, which may contain `$(location)` placeholders.
      targets: A list of additional targets (other than the calling rule's `deps`)
          that should be searched for substitutable labels.

    Returns:
      A list of strings with any `$(location)` placeholders filled in.
    """
    return [ctx.expand_location(value, targets) for value in values]

def get_output_groups(targets, group_name):
    """Returns a list containing the files of the given output group from each target in a list.

    The returned list may not be the same size as `targets` if some of the targets do not contain
    the requested output group. This is not an error.

    Args:
        targets: A list of targets.
        group_name: The name of the output group.

    Returns:
        A list of `depset`s of `File`s from the requested output group for each target.
    """
    groups = []

    for target in targets:
        group = getattr(target[OutputGroupInfo], group_name, None)
        if group:
            groups.append(group)

    return groups

def get_providers(targets, provider, map_fn = None):
    """Returns a list containing the given provider (or a field) from each target in the list.

    The returned list may not be the same size as `targets` if some of the targets do not contain
    the requested provider. This is not an error.

    The main purpose of this function is to make this common operation more readable and prevent
    mistyping the list comprehension.

    Args:
        targets: A list of targets.
        provider: The provider to retrieve.
        map_fn: A function that takes a single argument and returns a single value. If this is
            present, it will be called on each provider in the list and the result will be
            returned in the list returned by `get_providers`.

    Returns:
        A list of the providers requested from the targets.
    """
    if map_fn:
        return [map_fn(target[provider]) for target in targets if provider in target]
    return [target[provider] for target in targets if provider in target]

def merge_runfiles(all_runfiles):
    """Merges a list of `runfiles` objects.

    Args:
        all_runfiles: A list containing zero or more `runfiles` objects to merge.

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

def objc_provider_framework_name(path):
    """Returns the name of the framework from an `objc` provider path.

    Args:
        path: A path that came from an `objc` provider.

    Returns:
        A string containing the name of the framework (e.g., `Foo` for `Foo.framework`).
    """
    return path.rpartition("/")[2].partition(".")[0]

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
        # Even though the docs say a File's `short_path` doesn't include the root,
        # Bazel special cases anything from an external repository and includes a
        # relative path (`../`) to the file. On the File's `owner` we can get the
        # `workspace_root` to try and line things up, but it is in the form of
        # "external/[name]". However the File's `path` does include the root and
        # leaves it in the "external/" form, so we just relativize based on that
        # instead.
        return paths.relativize(file.path, paths.join(root, package))
    elif root:
        # As above, but for generated files. The same mangling happens in
        # `short_path`, but since it is generated, the `path` includes the extra
        # output directories used by Bazel. So, we pick off the parent directory
        # segment that Bazel adds to the `short_path` and turn it into "external/"
        # so a relative path from the owner can be computed.
        short_path = file.short_path

        # Sanity check.
        if (not root.startswith("external/") or not short_path.startswith("../")):
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

def _workspace_relative_path(file):
    """Returns the path of a file relative to its workspace.

    Args:
        file: The `File` object.

    Returns:
        The path of the file relative to its workspace.
    """
    workspace_path = paths.join(file.root.path, file.owner.workspace_root)
    return paths.relativize(file.path, workspace_path)

def proto_import_path(f, proto_source_root):
    """ Returns the import path of a `.proto` file given its path.

    Args:
        f: The `File` object representing the `.proto` file.
        proto_source_root: The source root for the `.proto` file.

    Returns:
        The path the `.proto` file should be imported at.
    """
    if f.path.startswith(proto_source_root):
        return f.path[len(proto_source_root) + 1:]
    else:
        # Happens before Bazel 1.0, where proto_source_root was not
        # guaranteed to be a parent of the .proto file
        return _workspace_relative_path(f)

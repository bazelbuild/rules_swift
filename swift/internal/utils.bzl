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

def collect_transitive(targets, provider, key, direct = None):
    """Returns a `depset` that collects transitive information from providers.

    Args:
      targets: The list of targets whose providers should be accessed.
      provider: The provider containing the data to be merged. If the provider is
          not propagated by the target, it is ignored.
      key: The key containing the data in the provider to be collected.
      direct: A list of values that should become the direct members of the
          `depset`, if any.

    Returns:
      A `depset` whose transitive members are the value of the key in the given
      provider of each of the targets.
    """
    transitives = [
        getattr(target[provider], key)
        for target in targets
        if provider in target
    ]
    if direct:
        return depset(direct = direct, transitive = transitives)
    return depset(transitive = transitives)

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

def workspace_relative_path(file):
    """Returns the path of a file relative to its workspace.

    Args:
        file: The `File` object.

    Returns:
        The path of the file relative to its workspace.
    """
    workspace_path = paths.join(file.root.path, file.owner.workspace_root)
    return paths.relativize(file.path, workspace_path)

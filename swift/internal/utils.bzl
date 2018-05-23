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

load("@bazel_skylib//:lib.bzl", "paths")

def collect_transitive(targets, provider, key, direct=None):
  """Returns a `depset` that collects transitive information from providers.

  Args:
    targets: The list of targets whose providers should be accessed.
    provider: The provider containing the data to be merged. This can either be
        a declared provider object or a string denoting an old-style provider.
        If the provider is not propagated by the target, it is ignored.
    key: The key containing the data in the provider to be collected.
    direct: A list of values that should become the direct members of the
        `depset`, if any.

  Returns:
    A `depset` whose transitive members are the value of the key in the given
    provider of each of the targets.
  """
  if type(provider) == type(""):
    transitives = [getattr(getattr(target, provider), key)
                   for target in targets if hasattr(target, provider)]
  else:
    transitives = [getattr(target[provider], key)
                   for target in targets if provider in target]
  if direct:
    return depset(direct=direct, transitive=transitives)
  return depset(transitive=transitives)

def expand_locations(ctx, values, targets=[]):
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

def get_optionally(object, keypath, default=None):
  """Returns the value of a keypath evaluated on an object, or a default value.

  This is equivalent to repeatedly evaluating each individual key on the value
  before it, but short-circuiting and returning the default value if any of the
  fields does not exist.

  Args:
    object: The object upon which the keypath will be evaluated.
    keypath: The dot-separated keypath describing the fields to access on the
        object.
    default: The default value to return if any of the fields is not present. If
        not provied, `None` will be used.

  Returns:
    The value of the keypath, or the default value if evaluation failed.
  """
  keys = keypath.split(".")
  value = object
  for key in keys:
    if not hasattr(value, key):
      return default
    value = getattr(value, key)
  return value

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
                root=root,
                short_path=short_path,
            ))

    return paths.relativize(
        paths.join("external", short_path[3:]), paths.join(root, package))
  else:
    return paths.relativize(file.short_path, package)

def run_with_optional_wrapper(
    actions,
    executable_name,
    inputs,
    outputs,
    arguments=[],
    env={},
    execution_requirements={},
    mnemonic=None,
    toolchain_root=None,
    wrapper_executable=None):
  """Runs a command with an optional wrapper executable.

  Args:
    actions: The context's actions object.
    executable_name: The name of the executable to spawn (e.g., `swiftc`).
    inputs: A list of sequences or a list of `depset`s containing inputs to the
        action.
    outputs: A list of files that are outputs of the action.
    arguments: A list of `Args` objects that are arguments to the process being
        invoked.
    env: A dictionary of environment variables for the process.
    execution_requirements: Information for scheduling the action.
    mnemonic: A one-word description of the action.
    wrapper_executable: An executable that should be used to wrap the process
        being spawned. If `None`, the process will be invoked via the shell
        instead.
  """
  if wrapper_executable:
    command_args = actions.args()
    command_args.add(executable_name)

    actions.run(
        arguments=[command_args] + arguments,
        executable=wrapper_executable,
        env=env,
        execution_requirements=execution_requirements,
        inputs=inputs,
        mnemonic=mnemonic,
        outputs=outputs)
  else:
    actions.run(
        arguments=arguments,
        env=env,
        executable="{}/bin/{}".format(toolchain_root, executable_name),
        execution_requirements=execution_requirements,
        inputs=inputs,
        mnemonic=mnemonic,
        outputs=outputs)

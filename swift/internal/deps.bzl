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

def swift_deps_libraries(deps):
  """Returns a list of `depset`s containing the transitive libraries of `deps`.

  This function handles the differences between the various providers that we
  support (`SwiftInfo` and `"cc"`) to provide a uniform API for collecting the
  transitive libraries that must be linked against when building a particular
  target.

  Args:
    deps: The list of targets from which the transitive libraries will be
        collected.

  Returns:
    The list of `depset`s that represent the transitive libraries among `deps`.
  """
  depsets = []

  for dep in deps:
    if SwiftInfo in dep:
      depsets.append(dep[SwiftInfo].transitive_libraries)
    elif apple_common.Objc in dep:
      # This is an `elif` because `swift_library` targets propagate both; so we
      # only want to pick up the libraries from the `Objc` provider if we didn't
      # already get them from a Swift provider.
      depsets.append(dep[apple_common.Objc].library)

    if SwiftCcLibsInfo in dep:
      depsets.append(dep[SwiftCcLibsInfo].libraries)

  return depsets

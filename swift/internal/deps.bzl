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

    This function handles the differences between the various providers that we support (`SwiftInfo`
    and `"cc"`) to provide a uniform API for collecting the transitive libraries that must be linked
    against when building a particular target.

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

    return [depset(transitive = depsets, order = "topological")]

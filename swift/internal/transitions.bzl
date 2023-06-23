# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""Configuration transitions used by the Swift build rules."""

visibility([
    "@build_bazel_rules_swift//swift/...",
])

def _cxx_interop_transition_impl(
        settings,  # @unused
        attr):
    mode = getattr(attr, "cxx_interop", None)

    # Coalesce some equivalent values to avoid creating a distinct configuration
    # for what is effectively the same behavior in the compiler.
    if mode == "off" or not mode:
        mode = ""

    return {
        "@build_bazel_rules_swift//swift:cxx_interop": mode,
    }

# Sets the `cxx_interop` build setting based on the `cxx_interop` attribute of
# the applying rule, if present.
cxx_interop_transition = transition(
    implementation = _cxx_interop_transition_impl,
    inputs = [],
    outputs = [
        "@build_bazel_rules_swift//swift:cxx_interop",
    ],
)

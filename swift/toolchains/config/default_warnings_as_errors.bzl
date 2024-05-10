# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Manages the default list of warnings that are upgraded to warnings."""

visibility([
    "@build_bazel_rules_swift//swift/toolchains/...",
])

_WARNINGS_AS_ERRORS_IDENTIFIERS = [
]

def default_warnings_as_errors_features():
    """Returns features to upgrade warnings to errors."""
    return [
        "swift.werror.{}".format(id)
        for id in _WARNINGS_AS_ERRORS_IDENTIFIERS
    ]

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

"""Common attributes used by multiple Swift build rules."""

load(":providers.bzl", "SwiftInfo")

def swift_common_rule_attrs(additional_deps_aspects = []):
    return {
        "data": attr.label_list(
            allow_files = True,
            doc = """
The list of files needed by this target at runtime.

Files and targets named in the `data` attribute will appear in the `*.runfiles`
area of this target, if it has one. This may include data files needed by a
binary or library, or other programs needed by it.
""",
        ),
        "deps": attr.label_list(
            aspects = additional_deps_aspects,
            doc = """
A list of targets that are dependencies of the target being built, which will be
linked into that target. Allowed kinds of dependencies are:

*   `swift_c_module`, `swift_import` and `swift_library` (or anything propagating `SwiftInfo`)
*   `cc_library` (or anything propagating `CcInfo`)

Additionally, on platforms that support Objective-C interop, `objc_library`
targets (or anything propagating the `apple_common.Objc` provider) are allowed
as dependencies. On platforms that do not support Objective-C interop (such as
Linux), those dependencies will be **ignored.**
""",
            providers = [
                [CcInfo],
                [SwiftInfo],
                [apple_common.Objc],
            ],
        ),
    }

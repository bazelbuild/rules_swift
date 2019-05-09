# Copyright 2019 The Bazel Authors. All rights reserved.
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

"""Attaches `SwiftClangModuleInfo` providers as needed to Swift targets.

Tulsi depends on this provider, so we can't remove it completely until a new release has been cut.
Moving it entirely to this aspect (which simulates the behavior that would have happened on the
rules themselves) allows us to remove it more easily in the future.
"""

load(":providers.bzl", "SwiftClangModuleInfo", "SwiftInfo")

def _legacy_swift_clang_module_info_aspect_impl(target, aspect_ctx):
    has_interesting_provider = False

    if SwiftInfo in target:
        has_interesting_provider = True
        swift_info = target[SwiftInfo]
        transitive_modulemaps = swift_info.transitive_modulemaps
    else:
        transitive_modulemaps = depset()

    if CcInfo in target:
        has_interesting_provider = True
        compilation_context = target[CcInfo].compilation_context
        transitive_compile_flags = depset(
            ["-I{}".format(path) for path in compilation_context.includes.to_list()] +
            ["-isystem{}".format(path) for path in compilation_context.system_includes.to_list()] +
            ["-iquote{}".format(path) for path in compilation_context.quote_includes.to_list()],
        )
        transitive_defines = compilation_context.defines
        transitive_headers = compilation_context.headers
    else:
        transitive_compile_flags = None
        transitive_defines = None
        transitive_headers = None

    if has_interesting_provider:
        return [SwiftClangModuleInfo(
            transitive_compile_flags = transitive_compile_flags,
            transitive_defines = transitive_defines,
            transitive_headers = transitive_headers,
            transitive_modulemaps = transitive_modulemaps,
        )]

    return []

legacy_swift_clang_module_info_aspect = aspect(
    implementation = _legacy_swift_clang_module_info_aspect_impl,
)

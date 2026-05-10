# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""Use a user-provided BUILD file for the explicit module targets for a single Xcode version."""

def _extract_all_module_names(text):
    names = []
    lines = text.split("\n")
    for i in range(len(lines)):
        if lines[i].rstrip() != "alias(":
            continue
        if i + 1 >= len(lines):
            fail("alias( at end of file; expected `name = \"...\",` on next line")
        s = lines[i + 1].strip()
        if not (s.startswith('name = "') and s.endswith('",')):
            fail(
                "expected `name = \"...\",` immediately after alias(, got: {}".format(s),
            )
        names.append(s[len('name = "'):-len('",')])
    return names

def _precomputed_xcode_explicit_module_repo_impl(rctx):
    content = rctx.read(rctx.attr.build_file)
    rctx.file("BUILD.bazel", content)
    rctx.file(
        "module_names.json",
        json.encode(_extract_all_module_names(content)),
    )

precomputed_xcode_explicit_module_repo = repository_rule(
    implementation = _precomputed_xcode_explicit_module_repo_impl,
    attrs = {
        "xcode_version": attr.string(
            mandatory = True,
            doc = "Canonical Xcode version string (e.g. 26.4.0.17E192).",
        ),
        "build_file": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Explicit module BUILD for the given Xcode.",
        ),
    },
    doc = "Per-Xcode explicit module config with a user-passed BUILD file.",
)

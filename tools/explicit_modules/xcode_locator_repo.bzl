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

"""Compile xcode-locator into its own repo so the binary is shareable."""

load("@bazel_tools//tools/osx:xcode_configure.bzl", "run_xcode_locator")

_LOCATOR_SRC = Label("@bazel_tools//tools/osx:xcode_locator.m")

def _xcode_locator_repo_impl(rctx):
    _, err = run_xcode_locator(rctx, _LOCATOR_SRC)
    if err:
        fail("xcode-locator compilation failed: " + err)
    rctx.file("BUILD.bazel", 'exports_files(["xcode-locator-bin"])\n')

xcode_locator_repo = repository_rule(
    implementation = _xcode_locator_repo_impl,
    doc = "Compile xcode-locator.m once; other repos reference the binary.",
)

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

"""Rule for running swiftc -frontend -verify for asserting diagnostics."""

load("//swift:swift_test.bzl", "swift_test")

_VERIFY_COPTS = [
    "-wmo",  # Disable incremental
    "-Xfrontend",
    "-verify",
]

def _swift_verify_test_impl(ctx):
    parent_providers = ctx.super()
    output_groups = None
    for provider in parent_providers:
        if type(provider) == "OutputGroupInfo":
            output_groups = provider
            break

    test_executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        content = "#!/bin/bash\nexit 0\n",
        is_executable = True,
        output = test_executable,
    )

    return [
        DefaultInfo(
            executable = test_executable,
            runfiles = ctx.runfiles(
                # NOTE: Some files from the compile must be propagated or the
                # compile action won't happen.
                transitive_files = output_groups.const_values,
            ),
        ),
    ]

def _swift_verify_test_initializer(name, copts = [], **_kwargs):
    return {
        "copts": (copts or []) + _VERIFY_COPTS,
        "discover_tests": False,
    }

swift_verify_test = rule(
    implementation = _swift_verify_test_impl,
    initializer = _swift_verify_test_initializer,
    parent = swift_test,
)

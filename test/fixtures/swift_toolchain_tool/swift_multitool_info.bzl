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

"""Exposes the resolved toolchain's `swift_multitool` to analysis tests."""

load("//swift:swift_common.bzl", "swift_common")

visibility(["//test/..."])

SwiftMultitoolTestInfo = provider(
    doc = "Carries `SwiftToolchainInfo.swift_multitool` of the toolchain.",
    fields = {
        "swift_multitool": "`SwiftToolchainInfo.swift_multitool`.",
    },
)

def _swift_multitool_info_impl(ctx):
    swift_toolchain = swift_common.get_toolchain(ctx)
    return [
        SwiftMultitoolTestInfo(
            swift_multitool = swift_toolchain.swift_multitool,
        ),
    ]

swift_multitool_info = rule(
    doc = "Returns the resolved Swift toolchain's `swift_multitool`.",
    implementation = _swift_multitool_info_impl,
    toolchains = swift_common.use_toolchain(),
)

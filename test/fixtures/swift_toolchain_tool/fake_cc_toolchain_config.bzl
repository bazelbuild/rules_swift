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

"""A fake C++ toolchain configuration for analysis tests of other platforms."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load(
    "@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl",
    "CcToolchainConfigInfo",
)

visibility(["//test/..."])

def _fake_cc_toolchain_config_impl(ctx):
    return [
        cc_common.create_cc_toolchain_config_info(
            abi_libc_version = "local",
            abi_version = "local",
            compiler = ctx.attr.compiler,
            ctx = ctx,
            host_system_name = "local",
            target_cpu = ctx.attr.target_cpu,
            target_libc = "unknown",
            target_system_name = ctx.attr.target_system_name,
            toolchain_identifier = ctx.label.name,
        ),
    ]

fake_cc_toolchain_config = rule(
    attrs = {
        "compiler": attr.string(mandatory = True),
        "target_cpu": attr.string(mandatory = True),
        "target_system_name": attr.string(mandatory = True),
    },
    doc = """\
A C++ toolchain configuration that only satisfies toolchain resolution; it
cannot compile or link anything.
""",
    implementation = _fake_cc_toolchain_config_impl,
    provides = [CcToolchainConfigInfo],
)

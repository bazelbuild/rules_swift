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

"""Minimal Objective-C framework import matching rules_apple's providers."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:swift_interop_info.bzl", "create_swift_interop_info")

def _framework_import_impl(ctx):
    module_map = ctx.file.module_map
    framework_dir = module_map.dirname.rpartition("/")[0]
    return [
        CcInfo(compilation_context = cc_common.create_compilation_context(
            headers = depset(ctx.files.hdrs + [module_map]),
            framework_includes = depset([framework_dir.rpartition("/")[0]]),
        )),
        create_swift_interop_info(module_map = module_map, module_name = ctx.attr.module_name),
    ]

framework_import = rule(
    implementation = _framework_import_impl,
    attrs = {
        "hdrs": attr.label_list(allow_files = [".h"]),
        "module_map": attr.label(allow_single_file = True, mandatory = True),
        "module_name": attr.string(mandatory = True),
    },
)

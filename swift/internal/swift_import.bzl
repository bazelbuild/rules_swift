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

"""Implementation of the `swift_import` rule."""

load(":attrs.bzl", "SWIFT_COMMON_RULE_ATTRS")
load(":compiling.bzl", "build_swift_info_provider")
load(":providers.bzl", "SwiftClangModuleInfo", "merge_swift_clang_module_infos")
load("@bazel_skylib//:lib.bzl", "dicts")

def _swift_import_impl(ctx):
  archives = ctx.files.archives
  deps = ctx.attr.deps
  swiftmodules = ctx.files.swiftmodules

  providers = [
      DefaultInfo(
          files=depset(direct=archives + swiftmodules),
          runfiles=ctx.runfiles(
              collect_data=True,
              collect_default=True,
              files=ctx.files.data,
          ),
      ),
      build_swift_info_provider(
          additional_cc_libs=[],
          compile_options=None,
          deps=deps,
          direct_additional_inputs=[],
          direct_defines=[],
          direct_libraries=archives,
          direct_linkopts=[],
          direct_swiftmodules=swiftmodules,
      ),
  ]

  # Only propagate `SwiftClangModuleInfo` if any of our deps does.
  if any([SwiftClangModuleInfo in dep for dep in deps]):
    clang_module = merge_swift_clang_module_infos(deps)
    providers.append(clang_module)

  return providers

swift_import = rule(
    attrs=dicts.add(SWIFT_COMMON_RULE_ATTRS, {
        "archives": attr.label_list(
            allow_empty=False,
            allow_files=["a"],
            doc="""
The list of `.a` files provided to Swift targets that depend on this target.
""",
            mandatory=True,
        ),
        "swiftmodules": attr.label_list(
            allow_empty=False,
            allow_files=["swiftmodule"],
            doc="""
The list of `.swiftmodule` files provided to Swift targets that depend on this
target.
""",
            mandatory=True,
        ),
    }),
    doc="""
Allows for the use of precompiled Swift modules as dependencies in other
`swift_library` and `swift_binary` targets.
""",
    implementation=_swift_import_impl,
)

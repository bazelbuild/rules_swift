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

"""Implementation of the `swift_library` rule."""

load(":api.bzl", "swift_common")
load(":compiling.bzl", "SWIFT_COMPILE_RULE_ATTRS", "swift_library_output_map")
load(":providers.bzl", "SwiftToolchainInfo")
load(":utils.bzl", "expand_locations")
load("@bazel_skylib//:lib.bzl", "dicts")

def _swift_library_impl(ctx):
  copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)
  linkopts = expand_locations(ctx, ctx.attr.linkopts, ctx.attr.swiftc_inputs)

  module_name = ctx.attr.module_name
  if not module_name:
    module_name = swift_common.derive_module_name(ctx.label)

  library_name = ctx.attr.module_link_name
  if library_name:
    copts.extend(["-module-link-name", library_name])

  # Bazel fails the build if you try to query a fragment that hasn't been
  # declared, even dynamically with `hasattr`/`getattr`. Thus, we have to use
  # other information to determine whether we can access the `objc`
  # configuration.
  toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
  objc_fragment = (ctx.fragments.objc if toolchain.supports_objc_interop
                   else None)

  compile_results = swift_common.compile_as_library(
      actions=ctx.actions,
      bin_dir=ctx.bin_dir,
      compilation_mode=ctx.var["COMPILATION_MODE"],
      label=ctx.label,
      module_name=module_name,
      srcs=ctx.files.srcs,
      swift_fragment=ctx.fragments.swift,
      toolchain=toolchain,
      additional_inputs=ctx.files.swiftc_inputs,
      cc_libs=ctx.attr.cc_libs,
      copts=copts,
      configuration=ctx.configuration,
      defines=ctx.attr.defines,
      deps=ctx.attr.deps,
      features=ctx.attr.features,
      library_name=library_name,
      linkopts=linkopts,
      objc_fragment=objc_fragment,
  )

  return compile_results.providers + [
      DefaultInfo(
          files=depset(direct=[
              compile_results.output_archive,
              compile_results.output_doc,
              compile_results.output_module,
          ]),
          runfiles=ctx.runfiles(
              collect_data=True,
              collect_default=True,
              files=ctx.files.data,
          ),
      ),
      OutputGroupInfo(**compile_results.output_groups),
  ]

swift_library = rule(
    attrs = dicts.add(
        SWIFT_COMPILE_RULE_ATTRS,
        {
            "module_link_name": attr.string(
                doc = """
The name of the library that should be linked to targets that depend on this
library. Supports auto-linking.
""",
                mandatory = False,
            ),
            # TODO(b/77853138): Remove once we support bundling from `data`.
            "resources": attr.label_list(
                allow_empty = True,
                allow_files = True,
                doc = """
Resources that should be processed by Xcode tools (such as interface builder
documents, Core Data models, asset catalogs, and so forth) and included in the
bundle that depends on this library.

This attribute is ignored when building Linux targets.
""",
                mandatory = False,
            ),
            # TODO(b/77853138): Remove once we support bundling from `data`.
            "structured_resources": attr.label_list(
                allow_empty = True,
                allow_files = True,
                doc = """
Files that should be included in the bundle that depends on this library without
any additional processing. The paths of these files relative to this library
target are preserved inside the bundle.

This attribute is ignored when building Linux targets.
""",
                mandatory = False,
            ),
        },
    ),
    doc = """
Compiles and links Swift code into a static library and Swift module.
""",
    fragments = [
        "objc",
        "swift",
    ],
    outputs = swift_library_output_map,
    implementation = _swift_library_impl,
)

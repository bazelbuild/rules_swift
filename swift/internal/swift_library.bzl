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
load(":compiling.bzl", "swift_library_output_map")
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

    # Bazel fails the build if you try to query a fragment that hasn't been declared, even
    # dynamically with `hasattr`/`getattr`. Thus, we have to use other information to determine
    # whether we can access the `objc` configuration.
    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    objc_fragment = (ctx.fragments.objc if toolchain.supports_objc_interop else None)

    compile_results = swift_common.compile_as_library(
        actions = ctx.actions,
        bin_dir = ctx.bin_dir,
        compilation_mode = ctx.var["COMPILATION_MODE"],
        label = ctx.label,
        module_name = module_name,
        srcs = ctx.files.srcs,
        swift_fragment = ctx.fragments.swift,
        toolchain = toolchain,
        additional_inputs = ctx.files.swiftc_inputs,
        cc_libs = ctx.attr.cc_libs,
        copts = copts,
        configuration = ctx.configuration,
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
        features = ctx.attr.features,
        genfiles_dir = ctx.genfiles_dir,
        library_name = library_name,
        linkopts = linkopts,
        objc_fragment = objc_fragment,
    )

    # TODO(b/79527231): Replace `instrumented_files` with a declared provider when it is available.
    return struct(
        instrumented_files = struct(
            dependency_attributes = ["deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        providers = compile_results.providers + [
            DefaultInfo(
                files = depset(direct = [
                    compile_results.output_archive,
                    compile_results.output_doc,
                    compile_results.output_module,
                ]),
                runfiles = ctx.runfiles(
                    collect_data = True,
                    collect_default = True,
                    files = ctx.files.data,
                ),
            ),
            OutputGroupInfo(**compile_results.output_groups),
        ],
    )

swift_library = rule(
    attrs = swift_common.library_rule_attrs(),
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

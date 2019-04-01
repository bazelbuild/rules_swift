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
load(":swift_c_module_aspect.bzl", "swift_c_module_aspect")
load(
    ":swift_info_through_non_swift_targets_aspect.bzl",
    "swift_info_through_non_swift_targets_aspect",
)
load(":utils.bzl", "expand_locations")

def _swift_library_impl(ctx):
    copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)
    linkopts = expand_locations(ctx, ctx.attr.linkopts, ctx.attr.swiftc_inputs)

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(ctx.label)

    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]

    feature_configuration = swift_common.configure_features(
        requested_features = ctx.features,
        swift_toolchain = toolchain,
        unsupported_features = ctx.disabled_features,
    )

    compile_results = swift_common.compile_as_library(
        actions = ctx.actions,
        bin_dir = ctx.bin_dir,
        label = ctx.label,
        module_name = module_name,
        srcs = ctx.files.srcs,
        toolchain = toolchain,
        additional_inputs = ctx.files.swiftc_inputs,
        alwayslink = ctx.attr.alwayslink,
        copts = copts,
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
        feature_configuration = feature_configuration,
        genfiles_dir = ctx.genfiles_dir,
        linkopts = linkopts,
    )

    direct_output_files = [
        compile_results.output_archive,
        compile_results.output_doc,
        compile_results.output_module,
    ]
    if compile_results.output_header:
        direct_output_files.append(compile_results.output_header)

    return compile_results.providers + [
        DefaultInfo(
            files = depset(direct = direct_output_files),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        OutputGroupInfo(**compile_results.output_groups),
    ]

swift_library = rule(
    attrs = swift_common.library_rule_attrs(additional_deps_aspects = [
        swift_c_module_aspect,
        swift_info_through_non_swift_targets_aspect,
    ]),
    doc = """
Compiles and links Swift code into a static library and Swift module.
""",
    outputs = swift_library_output_map,
    implementation = _swift_library_impl,
)

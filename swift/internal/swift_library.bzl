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
load(
    ":compiling.bzl",
    "find_swift_version_copt_value",
    "new_objc_provider",
    "swift_library_output_map",
)
load(":deps.bzl", "legacy_build_swift_info")
load(":linking.bzl", "register_libraries_to_link")
load(
    ":providers.bzl",
    "SwiftClangModuleInfo",
    "SwiftToolchainInfo",
    "merge_swift_clang_module_infos",
)
load(":swift_c_module_aspect.bzl", "swift_c_module_aspect")
load(
    ":swift_info_through_non_swift_targets_aspect.bzl",
    "swift_info_through_non_swift_targets_aspect",
)
load(":utils.bzl", "compact", "expand_locations")

def _maybe_parse_as_library_copts(srcs):
    """Returns a list of compiler flags depending on whether a `main.swift` file is present.

    Builds on Apple platforms typically don't use `swift_binary`; they use different linking logic
    (https://github.com/bazelbuild/rules_apple) to produce fat binaries and bundles. This means
    that all such application code will typically be in a `swift_library` target, and that
    includes a possible custom main entry point. For this reason, we need to support the creation
    of `swift_library` targets containing a `main.swift` file, which should *not* pass the
    `-parse-as-library` flag to the compiler.

    Args:
        srcs: A list of source files to check for the presence of `main.swift`.

    Returns:
        An empty list if `main.swift` was present in `srcs`, or a list containing a single
        element `"-parse-as-library"` if `main.swift` was not present.
    """
    use_parse_as_library = True
    for src in srcs:
        if src.basename == "main.swift":
            use_parse_as_library = False
            break
    return ["-parse-as-library"] if use_parse_as_library else []

def _swift_library_impl(ctx):
    additional_inputs = ctx.files.swiftc_inputs
    copts = expand_locations(ctx, ctx.attr.copts, additional_inputs)
    linkopts = expand_locations(ctx, ctx.attr.linkopts, additional_inputs)
    srcs = ctx.files.srcs

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(ctx.label)

    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    deps = ctx.attr.deps + swift_toolchain.implicit_deps

    feature_configuration = swift_common.configure_features(
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    compilation_outputs = swift_common.compile(
        actions = ctx.actions,
        additional_inputs = additional_inputs,
        bin_dir = ctx.bin_dir,
        copts = _maybe_parse_as_library_copts(srcs) + copts,
        defines = ctx.attr.defines,
        deps = deps,
        feature_configuration = feature_configuration,
        genfiles_dir = ctx.genfiles_dir,
        module_name = module_name,
        srcs = srcs,
        swift_toolchain = swift_toolchain,
        target_name = ctx.label.name,
    )

    library_to_link = register_libraries_to_link(
        actions = ctx.actions,
        alwayslink = ctx.attr.alwayslink,
        cc_feature_configuration = swift_common.cc_feature_configuration(
            feature_configuration = feature_configuration,
        ),
        is_dynamic = False,
        is_static = True,
        library_name = ctx.label.name,
        objects = compilation_outputs.object_files,
        swift_toolchain = swift_toolchain,
    )

    output_groups = {}
    if compilation_outputs.indexstore:
        output_groups["swift_index_store"] = depset([compilation_outputs.indexstore])

    direct_output_files = compact([
        compilation_outputs.generated_header,
        compilation_outputs.swiftdoc,
        compilation_outputs.swiftmodule,
        library_to_link.pic_static_library,
    ])

    providers = [
        DefaultInfo(
            files = depset(direct_output_files),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        OutputGroupInfo(**output_groups),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        legacy_build_swift_info(
            deps = deps,
            direct_additional_inputs = compilation_outputs.linker_inputs + additional_inputs,
            direct_libraries = compact([library_to_link.pic_static_library]),
            direct_linkopts = compilation_outputs.linker_flags + linkopts,
            direct_swiftdocs = [compilation_outputs.swiftdoc],
            direct_swiftmodules = [compilation_outputs.swiftmodule],
            module_name = module_name,
            swift_version = find_swift_version_copt_value(copts),
        ),
    ]

    # Propagate an `objc` provider if the toolchain supports Objective-C interop,
    # which allows `objc_library` targets to import `swift_library` targets.
    if swift_toolchain.supports_objc_interop:
        providers.append(new_objc_provider(
            defines = ctx.attr.defines,
            deps = deps,
            include_path = ctx.bin_dir.path,
            link_inputs = compilation_outputs.linker_inputs + additional_inputs,
            linkopts = compilation_outputs.linker_flags + linkopts,
            module_map = compilation_outputs.generated_module_map,
            static_archives = compact([library_to_link.pic_static_library]),
            swiftmodules = [compilation_outputs.swiftmodule],
            objc_header = compilation_outputs.generated_header,
        ))

    if any([SwiftClangModuleInfo in dep for dep in deps]):
        clang_module = merge_swift_clang_module_infos(deps)
        providers.append(clang_module)

    return providers

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

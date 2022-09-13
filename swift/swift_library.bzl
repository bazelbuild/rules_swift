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

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//swift/internal:attrs.bzl", "swift_deps_attr")
load(
    "//swift/internal:build_settings.bzl",
    "PerModuleSwiftCoptSettingInfo",
    "additional_per_module_swiftcopts",
)
load(
    "//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_EMIT_PRIVATE_SWIFTINTERFACE",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
)
load("//swift/internal:linking.bzl", "new_objc_provider")
load(
    "//swift/internal:output_groups.bzl",
    "supplemental_compilation_output_groups",
)
load("//swift/internal:toolchain_utils.bzl", "use_swift_toolchain")
load(
    "//swift/internal:utils.bzl",
    "compact",
    "expand_locations",
    "expand_make_variables",
    "get_providers",
    "include_developer_search_paths",
)
load(":providers.bzl", "SwiftCompilerPluginInfo", "SwiftInfo")
load(":swift_clang_module_aspect.bzl", "swift_clang_module_aspect")
load(":swift_common.bzl", "swift_common")

def _maybe_parse_as_library_copts(srcs):
    """Returns a list of compiler flags depending on `main.swift`'s presence.

    Builds on Apple platforms typically don't use `swift_binary`; they use
    different linking logic (https://github.com/bazelbuild/rules_apple) to
    produce fat binaries and bundles. This means that all such application code
    will typically be in a `swift_library` target, and that includes a possible
    custom main entry point. For this reason, we need to support the creation of
    `swift_library` targets containing a `main.swift` file, which should *not*
    pass the `-parse-as-library` flag to the compiler.

    Args:
        srcs: A list of source files to check for the presence of `main.swift`.

    Returns:
        An empty list if `main.swift` was present in `srcs`, or a list
        containing a single element `"-parse-as-library"` if `main.swift` was
        not present.
    """
    use_parse_as_library = True
    for src in srcs:
        if src.basename == "main.swift":
            use_parse_as_library = False
            break
    return ["-parse-as-library"] if use_parse_as_library else []

def _check_deps_are_disjoint(label, deps, private_deps):
    """Checks that the given sets of dependencies are disjoint.

    If the same target is listed in both sets, the build will fail.

    Args:
        label: The label of the target that will be printed in the failure
            message if the sets are not disjoint.
        deps: The list of public dependencies of the target.
        private_deps: The list of private dependencies of the target.
    """

    # If either set is empty, we don't need to check.
    if not deps or not private_deps:
        return

    deps_set = sets.make([str(dep.label) for dep in deps])
    private_deps_set = sets.make([str(dep.label) for dep in private_deps])
    intersection = sets.to_list(sets.intersection(deps_set, private_deps_set))
    if intersection:
        detail_msg = "\n".join(["  - {}".format(label) for label in intersection])
        fail(("In target '{}', 'deps' and 'private_deps' must be disjoint, " +
              "but the following targets were found in both:\n{}").format(
            label,
            detail_msg,
        ))

def _swift_library_impl(ctx):
    additional_inputs = ctx.files.swiftc_inputs

    # These can't use additional_inputs since expand_locations needs targets,
    # not files.
    copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)
    copts = expand_make_variables(ctx, copts, "copts")
    linkopts = expand_locations(ctx, ctx.attr.linkopts, ctx.attr.swiftc_inputs)
    linkopts = expand_make_variables(ctx, linkopts, "linkopts")
    srcs = ctx.files.srcs

    module_copts = additional_per_module_swiftcopts(
        ctx.label,
        ctx.attr._per_module_swiftcopt[PerModuleSwiftCoptSettingInfo],
    )
    if ctx.attr.linkstatic:
        copts.extend(["-static"])
    copts.extend(module_copts)

    extra_features = []
    if ctx.attr._config_emit_swiftinterface[BuildSettingInfo].value:
        extra_features.append(SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION)
        extra_features.append(SWIFT_FEATURE_EMIT_SWIFTINTERFACE)

    if ctx.attr._config_emit_private_swiftinterface[BuildSettingInfo].value:
        extra_features.append(SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION)
        extra_features.append(SWIFT_FEATURE_EMIT_PRIVATE_SWIFTINTERFACE)

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(ctx.label)

    swift_toolchain = swift_common.get_toolchain(ctx)
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features + extra_features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    deps = ctx.attr.deps
    private_deps = ctx.attr.private_deps
    _check_deps_are_disjoint(ctx.label, deps, private_deps)

    swift_infos = get_providers(deps, SwiftInfo)
    private_swift_infos = get_providers(private_deps, SwiftInfo)

    if ctx.attr.generates_header:
        generated_header_name = (
            ctx.attr.generated_header_name or
            "{}-Swift.h".format(ctx.label.name)
        )
    elif not ctx.attr.generated_header_name:
        generated_header_name = None
    else:
        fail(
            "'generated_header_name' may only be provided when " +
            "'generates_header' is True.",
            attr = "generated_header_name",
        )

    include_dev_srch_paths = include_developer_search_paths(ctx.attr)

    compile_result = swift_common.compile(
        actions = ctx.actions,
        additional_inputs = additional_inputs,
        cc_infos = get_providers(ctx.attr.deps, CcInfo),
        copts = _maybe_parse_as_library_copts(srcs) + copts,
        defines = ctx.attr.defines,
        feature_configuration = feature_configuration,
        generated_header_name = generated_header_name,
        include_dev_srch_paths = include_dev_srch_paths,
        module_name = module_name,
        objc_infos = get_providers(ctx.attr.deps, apple_common.Objc),
        package_name = ctx.attr.package_name,
        plugins = get_providers(ctx.attr.plugins, SwiftCompilerPluginInfo),
        private_swift_infos = private_swift_infos,
        srcs = srcs,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = ctx.label.name,
        workspace_name = ctx.workspace_name,
    )

    module_context = compile_result.module_context
    compilation_outputs = compile_result.compilation_outputs
    supplemental_outputs = compile_result.supplemental_outputs

    linking_context, linking_output = (
        swift_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            additional_inputs = additional_inputs,
            alwayslink = ctx.attr.alwayslink,
            compilation_outputs = compilation_outputs,
            feature_configuration = feature_configuration,
            include_dev_srch_paths = include_dev_srch_paths,
            label = ctx.label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in deps + private_deps
                if CcInfo in dep
            ],
            module_context = module_context,
            swift_toolchain = swift_toolchain,
            user_link_flags = linkopts,
        )
    )

    # Include the generated header (if any) as a rule output, so that a user
    # building the target can see its path and view it easily.
    generated_header_file = None
    if generated_header_name:
        for file in module_context.clang.compilation_context.direct_headers:
            if file.short_path.endswith(generated_header_name):
                generated_header_file = file
                break

    direct_output_files = compact([
        generated_header_file,
        module_context.clang.precompiled_module,
        module_context.swift.swiftdoc,
        module_context.swift.swiftinterface,
        module_context.swift.private_swiftinterface,
        module_context.swift.swiftmodule,
        module_context.swift.swiftsourceinfo,
        linking_output.library_to_link.static_library,
        linking_output.library_to_link.pic_static_library,
    ])

    implicit_deps_providers = swift_toolchain.implicit_deps_providers
    providers = [
        DefaultInfo(
            files = depset(direct_output_files),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        CcInfo(
            compilation_context = module_context.clang.compilation_context,
            linking_context = linking_context,
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps", "private_deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        swift_common.create_swift_info(
            modules = [module_context],
            # Note that private_deps are explicitly omitted here; they should
            # not propagate.
            swift_infos = swift_infos,
        ),
        OutputGroupInfo(
            **supplemental_compilation_output_groups(supplemental_outputs)
        ),
    ]

    # Propagate an `apple_common.Objc` provider with linking info about the
    # library so that linking with Apple Starlark APIs/rules works correctly.
    # TODO(b/171413861): This can be removed when the Obj-C rules are migrated
    # to use `CcLinkingContext`.
    providers.append(new_objc_provider(
        additional_link_inputs = additional_inputs,
        additional_objc_infos = implicit_deps_providers.objc_infos,
        alwayslink = ctx.attr.alwayslink,
        deps = deps + private_deps,
        feature_configuration = feature_configuration,
        is_test = ctx.attr.testonly,
        module_context = module_context,
        libraries_to_link = [linking_output.library_to_link],
        user_link_flags = linkopts,
        swift_toolchain = swift_toolchain,
    ))

    return providers

swift_library = rule(
    attrs = dicts.add(
        swift_common.library_rule_attrs(additional_deps_aspects = [
            swift_clang_module_aspect,
        ]),
        {
            "private_deps": swift_deps_attr(
                aspects = [swift_clang_module_aspect],
                doc = """\
A list of targets that are implementation-only dependencies of the target being
built. Libraries/linker flags from these dependencies will be propagated to
dependent for linking, but artifacts/flags required for compilation (such as
.swiftmodule files, C headers, and search paths) will not be propagated.
""",
            ),
        },
    ),
    doc = """\
Compiles and links Swift code into a static library and Swift module.
""",
    fragments = ["cpp"],
    implementation = _swift_library_impl,
    toolchains = use_swift_toolchain(),
)

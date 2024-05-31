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
load(
    "@build_bazel_rules_swift//swift/internal:attrs.bzl",
    "swift_deps_attr",
    "swift_library_rule_attrs",
)
load(
    "@build_bazel_rules_swift//swift/internal:build_settings.bzl",
    "PerModuleSwiftCoptSettingInfo",
    "additional_per_module_swiftcopts",
)
load(
    "@build_bazel_rules_swift//swift/internal:compiling.bzl",
    "compile",
)
load(
    "@build_bazel_rules_swift//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
)
load(
    "@build_bazel_rules_swift//swift/internal:features.bzl",
    "configure_features",
)
load(
    "@build_bazel_rules_swift//swift/internal:linking.bzl",
    "create_linking_context_from_compilation_outputs",
)
load(
    "@build_bazel_rules_swift//swift/internal:output_groups.bzl",
    "supplemental_compilation_output_groups",
)
load(
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    "SwiftCompilerPluginInfo",
)
load(
    "@build_bazel_rules_swift//swift/internal:toolchain_utils.bzl",
    "get_swift_toolchain",
    "use_swift_toolchain",
)
load(
    "@build_bazel_rules_swift//swift/internal:utils.bzl",
    "compact",
    "expand_locations",
    "get_compilation_contexts",
    "get_providers",
)
load(":module_name.bzl", "derive_swift_module_name")
load(":providers.bzl", "SwiftInfo", "SwiftOverlayInfo")
load(":swift_clang_module_aspect.bzl", "swift_clang_module_aspect")

visibility("public")

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
    linkopts = expand_locations(ctx, ctx.attr.linkopts, ctx.attr.swiftc_inputs)
    srcs = ctx.files.srcs

    module_copts = additional_per_module_swiftcopts(
        ctx.label,
        ctx.attr._per_module_swiftcopt[PerModuleSwiftCoptSettingInfo],
    )
    copts.extend(module_copts)

    extra_features = []

    if ctx.attr.library_evolution:
        extra_features.append(SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION)
        extra_features.append(SWIFT_FEATURE_EMIT_SWIFTINTERFACE)

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = derive_swift_module_name(ctx.label)

    swift_toolchain = get_swift_toolchain(ctx)
    feature_configuration = configure_features(
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

    compile_result = compile(
        actions = ctx.actions,
        additional_inputs = additional_inputs,
        compilation_contexts = get_compilation_contexts(ctx.attr.deps),
        copts = _maybe_parse_as_library_copts(srcs) + copts,
        defines = ctx.attr.defines,
        feature_configuration = feature_configuration,
        generated_header_name = generated_header_name,
        module_name = module_name,
        plugins = get_providers(ctx.attr.plugins, SwiftCompilerPluginInfo),
        private_swift_infos = private_swift_infos,
        srcs = srcs,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = ctx.label.name,
    )

    module_context = compile_result.module_context
    compilation_outputs = compile_result.compilation_outputs
    supplemental_outputs = compile_result.supplemental_outputs

    linking_context, linking_output = (
        create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            additional_inputs = additional_inputs,
            alwayslink = ctx.attr.alwayslink,
            compilation_outputs = compilation_outputs,
            feature_configuration = feature_configuration,
            label = ctx.label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in deps + private_deps
                if CcInfo in dep
            ] + [
                dep[SwiftOverlayInfo].linking_context
                for dep in deps + private_deps
                if SwiftOverlayInfo in dep
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
            if file.basename == generated_header_name:
                generated_header_file = file
                break

    direct_output_files = compact([
        generated_header_file,
        module_context.clang.precompiled_module,
        module_context.swift.swiftdoc,
        module_context.swift.swiftinterface,
        module_context.swift.swiftmodule,
        module_context.swift.swiftsourceinfo,
        linking_output.library_to_link.static_library,
        linking_output.library_to_link.pic_static_library,
    ])

    return [
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
        compile_result.swift_info,
        OutputGroupInfo(
            **supplemental_compilation_output_groups(supplemental_outputs)
        ),
    ]

swift_library = rule(
    attrs = dicts.add(
        swift_library_rule_attrs(additional_deps_aspects = [
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
            # TODO(b/301253335): Once AEGs are enabled in Bazel, set the swift toolchain type in the
            # exec configuration of `plugins` attribute and enable AEGs in swift_library.
            "_use_auto_exec_groups": attr.bool(default = False),
        },
    ),
    doc = """\
Compiles and links Swift code into a static library and Swift module.
""",
    fragments = ["cpp"],
    implementation = _swift_library_impl,
    toolchains = use_swift_toolchain(),
)

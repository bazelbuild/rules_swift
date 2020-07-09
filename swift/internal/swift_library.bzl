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

load(":attrs.bzl", "swift_deps_attr")
load(
    ":compiling.bzl",
    "find_swift_version_copt_value",
    "new_objc_provider",
    "output_groups_from_compilation_outputs",
    "swift_library_output_map",
)
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS",
)
load(":linking.bzl", "register_libraries_to_link")
load(":providers.bzl", "SwiftInfo", "SwiftToolchainInfo")
load(":swift_common.bzl", "swift_common")
load(
    ":utils.bzl",
    "compact",
    "create_cc_info",
    "expand_locations",
    "get_providers",
)
load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

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
        detail_msg = ["\n  - {}".format(label) for label in intersection]
        fail(("In target '{}', 'deps' and 'private_deps' must be disjoint, " +
              "but the following targets were found in both: {}").format(
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

    extra_features = []
    if ctx.attr._config_emit_swiftinterface[BuildSettingInfo].value:
        extra_features.append(SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION)
        extra_features.append(SWIFT_FEATURE_EMIT_SWIFTINTERFACE)

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(ctx.label)

    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features + extra_features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    implicit_deps = swift_common.get_implicit_deps(
        feature_configuration = feature_configuration,
        swift_toolchain = swift_toolchain,
    )
    if swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS,
    ):
        # The implicit deps can be added to the private deps; since they are
        # added to the compilation of every library, they don't need to be
        # propagated. However, it's not an error to list one of the implicit
        # deps in "deps", either, so we need to make sure not to pass them in to
        # `_check_deps_are_disjoint`.
        deps = ctx.attr.deps
        private_deps = ctx.attr.private_deps + implicit_deps
        _check_deps_are_disjoint(ctx.label, deps, ctx.attr.private_deps)
    elif ctx.attr.private_deps:
        fail(
            ("In target '{}', 'private_deps' cannot be used because this " +
             "version of the Swift toolchain does not support " +
             "implementation-only imports.").format(ctx.label),
            attr = "private_deps",
        )
    else:
        deps = ctx.attr.deps
        private_deps = []

    compilation_outputs = swift_common.compile(
        actions = ctx.actions,
        additional_inputs = additional_inputs,
        bin_dir = ctx.bin_dir,
        copts = _maybe_parse_as_library_copts(srcs) + copts,
        defines = ctx.attr.defines,
        deps = deps + private_deps,
        feature_configuration = feature_configuration,
        generated_header_name = ctx.attr.generated_header_name,
        genfiles_dir = ctx.genfiles_dir,
        module_name = module_name,
        srcs = srcs,
        swift_toolchain = swift_toolchain,
        target_name = ctx.label.name,
    )

    # If a module map was created for the generated header, propagate it as a
    # Clang module so that it is passed as a module input to upstream
    # compilation actions.
    if compilation_outputs.generated_module_map:
        clang_module = swift_common.create_clang_module(
            compilation_context = cc_common.create_compilation_context(
                headers = depset([compilation_outputs.generated_header]),
            ),
            module_map = compilation_outputs.generated_module_map,
            # TODO(b/142867898): Precompile the module and place it here.
            precompiled_module = None,
        )
    else:
        clang_module = None

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

    direct_output_files = compact([
        compilation_outputs.generated_header,
        compilation_outputs.swiftdoc,
        compilation_outputs.swiftinterface,
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
        OutputGroupInfo(**output_groups_from_compilation_outputs(
            compilation_outputs = compilation_outputs,
        )),
        create_cc_info(
            additional_inputs = additional_inputs,
            cc_infos = get_providers(deps, CcInfo),
            compilation_outputs = compilation_outputs,
            defines = ctx.attr.defines,
            includes = [ctx.bin_dir.path],
            libraries_to_link = [library_to_link],
            private_cc_infos = get_providers(private_deps, CcInfo),
            user_link_flags = linkopts,
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps", "private_deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        swift_common.create_swift_info(
            modules = [
                swift_common.create_module(
                    name = module_name,
                    clang = clang_module,
                    swift = swift_common.create_swift_module(
                        defines = ctx.attr.defines,
                        swiftdoc = compilation_outputs.swiftdoc,
                        swiftinterface = compilation_outputs.swiftinterface,
                        swiftmodule = compilation_outputs.swiftmodule,
                    ),
                ),
            ],
            # Note that private_deps are explicitly omitted here; they should
            # not propagate.
            swift_infos = get_providers(deps, SwiftInfo),
            swift_version = find_swift_version_copt_value(copts),
        ),
    ]

    # Propagate an `objc` provider if the toolchain supports Objective-C
    # interop, which allows `objc_library` targets to import `swift_library`
    # targets.
    if swift_toolchain.supports_objc_interop:
        providers.append(new_objc_provider(
            # We must include private_deps here because some of the information
            # propagated here is related to linking.
            # TODO(allevato): This means we can't yet completely avoid
            # propagating headers/module maps from impl-only Obj-C dependencies.
            deps = deps + private_deps,
            link_inputs = compilation_outputs.linker_inputs + additional_inputs,
            linkopts = compilation_outputs.linker_flags + linkopts,
            module_map = compilation_outputs.generated_module_map,
            static_archives = compact([library_to_link.pic_static_library]),
            swiftmodules = [compilation_outputs.swiftmodule],
            objc_header = compilation_outputs.generated_header,
        ))

    return providers

swift_library = rule(
    attrs = dicts.add(
        swift_common.library_rule_attrs(additional_deps_aspects = [
            swift_common.swift_clang_module_aspect,
        ]),
        {
            "private_deps": swift_deps_attr(
                aspects = [swift_common.swift_clang_module_aspect],
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
    outputs = swift_library_output_map,
    implementation = _swift_library_impl,
    fragments = ["cpp"],
)

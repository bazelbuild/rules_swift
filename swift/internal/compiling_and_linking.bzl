"""
Utility function to compile and link swift source files into a module,
producing a similar set of providers as swift_library.
"""

load(
    "//swift:providers.bzl",
    "SwiftInfo",
)
load(
    "//swift/internal:compiling.bzl",
    "compile",
)
load(
    "//swift/internal:features.bzl",
    "configure_features",
)
load(
    "//swift/internal:linking.bzl",
    "create_linking_context_from_compilation_outputs",
    "new_objc_provider",
)
load(
    "//swift/internal:output_groups.bzl",
    "supplemental_compilation_output_groups",
)
load(
    "//swift/internal:providers.bzl",
    "create_swift_info",
)
load(
    "//swift/internal:toolchain_utils.bzl",
    "get_swift_toolchain",
)
load(
    "//swift/internal:utils.bzl",
    "get_providers",
    "include_developer_search_paths",
)

def compile_and_create_linking_context(
        *,
        attr,
        ctx,
        target_label,
        module_name,
        swift_srcs,
        compiler_deps):
    """ Compiles the Swift source files into a module and creates a linking context from it.

    Args:
        attr: The attributes of the target for which the module is being compiled.
        ctx: The context of the aspect or rule.
        target_label: The label of the target for which the module is being compiled.
        module_name: The name of the Swift module that should be compiled from the source files.
        swift_srcs: List of Swift source files to be compiled into the module.
        compiler_deps: List of dependencies required to compile the source files.

    Returns:
        A struct with the following fields:
        direct_cc_info: CcInfo provider generated directly by this target.
        direct_objc_info: apple_common.Objc provider generated directly by this target.
        direct_swift_info: SwiftInfo provider generated directly by this target.
        direct_output_group_info: OutputGroupInfo provider generated directly by this target.
    """

    # Extract the swift toolchain and configure the features:
    swift_toolchain = get_swift_toolchain(ctx)
    feature_configuration = configure_features(
        ctx = ctx,
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    # Compile the generated Swift source files as a module:
    include_dev_srch_paths = include_developer_search_paths(attr)
    compile_result = compile(
        actions = ctx.actions,
        cc_infos = get_providers(compiler_deps, CcInfo),
        copts = ["-parse-as-library"],
        feature_configuration = feature_configuration,
        include_dev_srch_paths = include_dev_srch_paths,
        module_name = module_name,
        objc_infos = get_providers(compiler_deps, apple_common.Objc),
        package_name = None,
        srcs = swift_srcs,
        swift_toolchain = swift_toolchain,
        swift_infos = get_providers(compiler_deps, SwiftInfo),
        target_name = target_label.name,
        workspace_name = ctx.workspace_name,
    )

    module_context = compile_result.module_context
    compilation_outputs = compile_result.compilation_outputs
    supplemental_outputs = compile_result.supplemental_outputs

    # Create the linking context from the compilation outputs:
    linking_context, linking_output = (
        create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            compilation_outputs = compilation_outputs,
            feature_configuration = feature_configuration,
            include_dev_srch_paths = include_dev_srch_paths,
            label = target_label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in compiler_deps
                if CcInfo in dep
            ],
            module_context = module_context,
            swift_toolchain = swift_toolchain,
        )
    )

    # Gather the transitive cc info providers:
    transitive_cc_infos = get_providers(compiler_deps, CcInfo)

    # Gather the transitive objc info providers:
    transitive_objc_infos = get_providers(compiler_deps, apple_common.Objc)

    # Gather the transitive swift info providers:
    transitive_swift_infos = get_providers(compiler_deps, SwiftInfo)

    # Create the direct cc info provider:
    direct_cc_info = cc_common.merge_cc_infos(
        direct_cc_infos = [
            CcInfo(
                compilation_context = module_context.clang.compilation_context,
                linking_context = linking_context,
            ),
        ],
        cc_infos = transitive_cc_infos,
    )

    # Create the direct objc info provider:
    direct_objc_info = new_objc_provider(
        additional_objc_infos = (
            transitive_objc_infos +
            swift_toolchain.implicit_deps_providers.objc_infos
        ),
        deps = [],
        feature_configuration = feature_configuration,
        is_test = False,
        module_context = module_context,
        libraries_to_link = [linking_output.library_to_link],
        swift_toolchain = swift_toolchain,
    )

    # Create the direct swift info provider:
    direct_swift_info = create_swift_info(
        modules = [module_context],
        swift_infos = transitive_swift_infos,
    )

    # Create the direct output group info provider:
    direct_output_group_info = OutputGroupInfo(
        **supplemental_compilation_output_groups(
            supplemental_outputs,
        )
    )

    return struct(
        direct_cc_info = direct_cc_info,
        direct_objc_info = direct_objc_info,
        direct_swift_info = direct_swift_info,
        direct_output_group_info = direct_output_group_info,
    )

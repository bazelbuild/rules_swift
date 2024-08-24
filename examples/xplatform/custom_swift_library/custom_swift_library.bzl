"""
A custom Bazel rule which behaves similar to swift_library but it autogenerates its source files.
"""

load(
    "@bazel_skylib//lib:dicts.bzl",
    "dicts",
)
load(
    "//swift:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)
load(
    "//swift:swift_common.bzl",
    "swift_common",
)

def _compact(sequence):
    return [item for item in sequence if item != None]

def _custom_swift_library_impl(ctx):

    # Create the swift file:
    custom_file_format = """\
{}
public struct {} {{
    let regular: {}

    public init(regular: {}) {{
        self.regular = regular
    }}
}}
"""
    custom_file_content = custom_file_format.format(
        ctx.attr.regular_import,
        ctx.attr.custom_type_name,
        ctx.attr.regular_type_name,
        ctx.attr.regular_type_name,
    )
    custom_file = ctx.actions.declare_file("{}.swift".format(ctx.label.name))
    ctx.actions.write(custom_file, custom_file_content)

    # Compile the swift file into a library:
    direct_providers = swift_common.compile_and_create_linking_context(
        attr = ctx.attr,
        ctx = ctx,
        target_label = ctx.label,
        module_name = getattr(ctx.attr, "module_name", ctx.label.name),
        swift_srcs = [custom_file],
        compiler_deps = getattr(ctx.attr, "deps", []),
    )

    # Map the providers:
    direct_cc_info = direct_providers.direct_cc_info
    direct_objc_info = direct_providers.direct_objc_info
    direct_swift_info = direct_providers.direct_swift_info
    direct_output_group_info = direct_providers.direct_output_group_info
    direct_files = _compact(
        [module.swift.swiftdoc for module in direct_swift_info.direct_modules] +
        [module.swift.swiftinterface for module in direct_swift_info.direct_modules] +
        [module.swift.private_swiftinterface for module in direct_swift_info.direct_modules] +
        [module.swift.swiftmodule for module in direct_swift_info.direct_modules] +
        [module.swift.swiftsourceinfo for module in direct_swift_info.direct_modules],
    )

    return [
        DefaultInfo(
            files = depset(
                direct_files,
                transitive = [depset([custom_file])],
            ),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        direct_cc_info,
        direct_objc_info,
        direct_swift_info,
        direct_output_group_info,
    ]

custom_swift_library = rule(
    attrs = dicts.add(
        swift_common.library_rule_attrs(
            additional_deps_aspects = [
                swift_clang_module_aspect,
            ],
            requires_srcs = False,
        ),
        {
            "regular_import": attr.string(),
            "regular_type_name": attr.string(),
            "custom_type_name": attr.string(),
        },
    ),
    doc = """
Demonstrates how to create a custom rule which propagates the same providers 
as swift_library, while having custom logic to generate the source files and other
configurations.
""",
    fragments = ["cpp"],
    implementation = _custom_swift_library_impl,
    toolchains = swift_common.use_toolchain(),
)

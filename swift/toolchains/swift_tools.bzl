"""Rules for defining Swift toolchain executables as explicit dependencies.

This module provides the `swift_tools` rule, which allows users to specify
Swift toolchain tools (such as the Swift driver, autolink extractor, and
symbol graph extractor) as labels. These tools are then propagated via the
`SwiftToolsInfo` provider, making them available in the execution environment
as explicit dependencies.
"""

load("//swift:providers.bzl", "SwiftToolsInfo")

def _swift_tools_impl(ctx):
    """Implementation of the swift_tools rule.

    Args:
        ctx: The rule context.

    Returns:
        A list containing a SwiftToolsInfo provider.
    """
    return [
        SwiftToolsInfo(
            swift_driver = ctx.file.swift_driver,
            swift_autolink_extract = ctx.file.swift_autolink_extract,
            swift_symbolgraph_extract = ctx.file.swift_symbolgraph_extract,
            additional_linker_inputs = depset(ctx.files.additional_linker_inputs),
        ),
    ]

swift_tools = rule(
    doc = """\
Defines Swift toolchain executables that can be used as explicit dependencies.

This rule allows you to specify Swift toolchain tools as labels, making them
available in the execution environment. The tools are propagated via the
`SwiftToolsInfo` provider.

Example:
    swift_tools(
        name = "my_swift_tools",
        swift_driver = "//path/to:swift-driver",
        swift_autolink_extract = "//path/to:swift-autolink-extract",
        swift_symbolgraph_extract = "//path/to:swift-symbolgraph-extract",
        additional_linker_inputs = glob("path/to/runtime/**"),
    )
""",
    implementation = _swift_tools_impl,
    attrs = {
        "swift_driver": attr.label(
            allow_single_file = True,
            doc = "Label of the Swift driver executable.",
            mandatory = True,
        ),
        "swift_autolink_extract": attr.label(
            allow_single_file = True,
            doc = "Label of the swift-autolink-extract executable.",
            mandatory = True,
        ),
        "swift_symbolgraph_extract": attr.label(
            allow_single_file = True,
            doc = "Label of the swift-symbolgraph-extract executable.",
            mandatory = True,
        ),
        "additional_linker_inputs": attr.label_list(
            allow_files = True,
            doc = "List of labels to include in the input-tree for swift link actions.",
            mandatory = True,
        ),
    },
    provides = [SwiftToolsInfo],
)

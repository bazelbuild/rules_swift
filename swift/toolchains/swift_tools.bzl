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
            additional_inputs = ctx.files.additional_inputs,
            swift = ctx.file.swift,
            swift_runfiles = ctx.files.swift_runfiles,
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
        swift = "//path/to:swift",
        swift_driver = "//path/to:swift-driver",
        swift_autolink_extract = "//path/to:swift-autolink-extract",
        swift_symbolgraph_extract = "//path/to:swift-symbolgraph-extract",
        additional_inputs = glob("path/to/runtime/**"),
        swift_runfiles = glob(["path/to/bin/*", "path/to/lib/swift/pm/**"]),
    )
""",
    implementation = _swift_tools_impl,
    attrs = {
        "additional_inputs": attr.label_list(
            allow_files = True,
            doc = "List of labels to include in the input-tree when invoking these tools.",
            mandatory = True,
        ),
        "swift": attr.label(
            allow_single_file = True,
            doc = """\
Label of the `swift` multi-tool driver executable (the one that dispatches
`swift build`, `swift package`, etc.). Optional; if omitted, consumers fall back
to invoking `swift_driver` with `--driver-mode=swift`.
""",
        ),
        "swift_autolink_extract": attr.label(
            allow_single_file = True,
            doc = "Label of the swift-autolink-extract executable.",
            mandatory = True,
        ),
        "swift_driver": attr.label(
            allow_single_file = True,
            doc = "Label of the Swift driver executable.",
            mandatory = True,
        ),
        "swift_runfiles": attr.label_list(
            allow_files = True,
            doc = """\
Labels of files needed at runtime to run the `swift` multi-tool, such as the
`swift-package` and `swift-build` executables that it dispatches to and
SwiftPM's runtime libraries. Unlike `additional_inputs`, these are not added
to compile actions; they are only added to the runfiles of
`swift_toolchain_tool` targets.
""",
        ),
        "swift_symbolgraph_extract": attr.label(
            allow_single_file = True,
            doc = "Label of the swift-symbolgraph-extract executable.",
            mandatory = True,
        ),
    },
    provides = [SwiftToolsInfo],
)

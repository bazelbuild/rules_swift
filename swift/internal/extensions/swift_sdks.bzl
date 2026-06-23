"""Shared building blocks for Swift SDK repository rules.

A "Swift SDK" is an artifact bundle published by swift.org for cross-compiling
Swift to a platform the host toolchain cannot target by itself (the bundles that
`swift sdk install` consumes). The per-platform extensions (e.g. `wasm_sdk`,
`android_sdk`) define repository rules that download such a bundle and generate
a `swift_toolchain` + rules_cc `cc_toolchain` for the target; this module holds
the helpers and BUILD-file templates they share.

Because the Swift module format is not stable across compiler versions, a Swift
SDK must come from exactly the same release as the host toolchain it is paired
with; the `swift` module extension enforces this by deriving both from the same
`swift.toolchain` tag.
"""

# Files in the host toolchain that compile actions need: the driver/frontend
# binaries, their libraries, and clang's builtin headers (used by the clang
# importer when the Swift SDK's resource directory does not bundle them).
# buildifier: disable=unused-variable
_HOST_COMPILER_INPUTS = "swift_sdk_compiler_inputs"

# Files in the host toolchain that link actions driven by its clang need.
# buildifier: disable=unused-variable
_HOST_LINKER_INPUTS = "swift_sdk_linker_inputs"

# buildifier: disable=unused-variable
_CC_TOOLCHAIN_TEMPLATE = """
cc_tool(
    name = "clang",
    src = "{clang}",
    data = {clang_data},
    tags = ["manual"],
)

cc_tool(
    name = "ar",
    src = "{ar}",
    tags = ["manual"],
)

cc_tool_map(
    name = "cc_tools",
    tags = ["manual"],
    tools = {{
        "@rules_cc//cc/toolchains/actions:ar_actions": ":ar",
        "@rules_cc//cc/toolchains/actions:assembly_actions": ":clang",
        "@rules_cc//cc/toolchains/actions:c_compile": ":clang",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions": ":clang",
        "@rules_cc//cc/toolchains/actions:link_actions": ":clang",
    }},
)
"""

# buildifier: disable=unused-variable
_CC_TOOLCHAIN_FOR_TARGET_TEMPLATE = """
cc_args(
    name = "cc_args_{suffix}",
    actions = [
        "@rules_cc//cc/toolchains/actions:compile_actions",
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = {args},
)

cc_args(
    name = "cc_link_args_{suffix}",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = {link_args},
)

cc_make_variable(
    name = "cc_target_triple_{suffix}",
    value = "{triple}",
    variable_name = "CC_TARGET_TRIPLE",
)

cc_toolchain(
    name = "cc_toolchain_{suffix}",
    args = [
        ":cc_args_{suffix}",
        ":cc_link_args_{suffix}",
    ],
    compiler = "clang",
    enabled_features = [
        "@rules_cc//cc/toolchains/args/archiver_flags:feature",
        "@rules_cc//cc/toolchains/args/libraries_to_link:feature",
        "@rules_cc//cc/toolchains/args/link_flags:feature",
        # Needed so `swift_binary(linkshared = True)` links a shared library
        # (passes `-shared` for the dynamic_library link action).
        "@rules_cc//cc/toolchains/args/shared_flag:feature",
    ],
    make_variables = [
        ":cc_target_triple_{suffix}",
    ],
    tool_map = ":cc_tools",
)
"""

# buildifier: disable=unused-variable
_SWIFT_TOOLCHAIN_TEMPLATE = """
swift_toolchain(
    name = "swift_toolchain_{suffix}",
    arch = "{arch}",
    copts = {copts},
    features = {features},
    linker_inputs = {linker_inputs},
    linkopts = {linkopts},
    os = "{os}",
    parsed_version = "{swift_version}",
    sdkroot = "{sdkroot}",
    swift_tools = ":tools",
    version_file = ".swift-version",
)
"""

# buildifier: disable=unused-variable
_BUILD_HEADER_TEMPLATE = """\
load("@rules_cc//cc/toolchains:args.bzl", "cc_args")
load("@rules_cc//cc/toolchains:make_variable.bzl", "cc_make_variable")
load("@rules_cc//cc/toolchains:tool.bzl", "cc_tool")
load("@rules_cc//cc/toolchains:tool_map.bzl", "cc_tool_map")
load("@rules_cc//cc/toolchains:toolchain.bzl", "cc_toolchain")
load("@rules_swift//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("@rules_swift//swift/toolchains:swift_tools.bzl", "swift_tools")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "sdk_files",
    srcs = glob(["{bundle_dir}/**"]),
)

swift_tools(
    name = "tools",
    swift_driver = "@{toolchain_repo}//:usr/bin/swiftc",
    swift_autolink_extract = "@{toolchain_repo}//:usr/bin/swift-autolink-extract",
    swift_symbolgraph_extract = "@{toolchain_repo}//:usr/bin/swift-symbolgraph-extract",
    additional_inputs = {compiler_inputs},
)
"""

# buildifier: disable=unused-variable
def _build_list(items, indent = "    "):
    """Formats a list of strings as a multi-line BUILD file list literal."""
    if not items:
        return "[]"
    lines = ["["]
    for item in items:
        lines.append("{}    \"{}\",".format(indent, item))
    lines.append(indent + "]")
    return "\n".join(lines)

# buildifier: disable=unused-variable
def _download_sdk_bundle(repository_ctx):
    """Downloads and extracts the Swift SDK artifact bundle for a repository.

    Returns:
        The name of the top-level `.artifactbundle` directory.
    """
    repository_ctx.download_and_extract(
        url = repository_ctx.attr.url,
        sha256 = repository_ctx.attr.sha256,
    )
    repository_ctx.file(".swift-version", repository_ctx.attr.swift_version)

    bundles = [
        entry.basename
        for entry in repository_ctx.path(".").readdir()
        if entry.basename.endswith(".artifactbundle")
    ]
    if len(bundles) != 1:
        fail(("Expected the archive at {} to contain exactly one " +
              ".artifactbundle directory, found: {}").format(
            repository_ctx.attr.url,
            bundles,
        ))
    return bundles[0]

# buildifier: disable=unused-variable
def _common_attrs():
    return {
        "sha256": attr.string(
            doc = "The expected SHA-256 of the SDK artifact bundle.",
            mandatory = True,
        ),
        "swift_version": attr.string(
            doc = "The Swift release version the SDK belongs to.",
            mandatory = True,
        ),
        "toolchain_repo": attr.string(
            doc = """\
Name of the `standalone_toolchain` repository providing the host tools that
this SDK is paired with.
""",
            mandatory = True,
        ),
        "url": attr.string(
            doc = "The download URL of the SDK artifact bundle.",
            mandatory = True,
        ),
    }

load("@aspect_bazel_lib//lib:docs.bzl", "stardoc_with_diff_test", "update_docs")
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:write_file.bzl", "write_file")

bzl_library(
    name = "doc",
    srcs = ["//doc:doc.bzl"],
    visibility = ["//doc:__pkg__"],
    deps = [
        "//mixed_language",
        "//proto",
        "//swift",
    ],
)

_DOC_SYMBOLS = {
    "api": [
        "create_swift_interop_info",
        "derive_swift_module_name",
        "is_swift_overlay",
        "swift_common",
    ],
    "providers": [
        "SwiftInfo",
        "SwiftToolchainInfo",
        "SwiftProtoCompilerInfo",
        "SwiftProtoInfo",
    ],
    "rules": [
        "swift_binary",
        "swift_compiler_plugin",
        "universal_swift_compiler_plugin",
        "swift_compiler_plugin_import",
        "swift_cross_import_overlay",
        "swift_feature_allowlist",
        "swift_import",
        "swift_interop_hint",
        "swift_library",
        "swift_library_group",
        "mixed_language_library",
        "swift_module_mapping",
        "swift_module_mapping_test",
        "swift_overlay",
        "swift_package_configuration",
        "swift_test",
        "swift_proto_library",
        "swift_proto_library_group",
        "swift_proto_compiler",
        "deprecated_swift_grpc_library",
        "deprecated_swift_proto_library",
    ],
}

_DOC_HEADERS = {
    "api": """\
<!-- Generated with Stardoc, Do Not Edit! -->
# Build API

The `swift_common` module provides API access to the behavior
implemented by the Swift build rules, so that other custom rules can
invoke Swift compilation and/or linking as part of their
implementation.

Some API is exposed as free functions outside of the `swift_common`
module.""",
    "providers": """\
<!-- Generated with Stardoc, Do Not Edit! -->

The providers described below are propagated and required by various Swift
build rules. Clients interested in writing custom rules that interface
with the rules in this package should use these providers to communicate
with the Swift build rules as needed.

On this page:

{}

""".format("\n".join(["  * [{0}](#{0})".format(sym) for sym in _DOC_SYMBOLS["providers"]])),
    "rules": """\
<!-- Generated with Stardoc, Do Not Edit! -->

${{moduleDocstring}}
On this page:

{}

""".format("\n".join(["  * [{0}](#{0})".format(sym) for sym in _DOC_SYMBOLS["rules"]])),
    "setup": """\
<!-- Generated with Stardoc, Do Not Edit! -->
# Workspace Setup""",
}

stardoc_with_diff_test(
    name = "api",
    bzl_library_target = "//doc:doc",
    header_template = ":api_header",
    symbol_names = _DOC_SYMBOLS["api"],
)

write_file(
    name = "api_header",
    out = "api_header.vm",
    content = _DOC_HEADERS["api"].splitlines(),
)

stardoc_with_diff_test(
    name = "providers",
    bzl_library_target = "//doc:doc",
    header_template = ":providers_header",
    symbol_names = _DOC_SYMBOLS["providers"],
)

write_file(
    name = "providers_header",
    out = "providers_header.vm",
    content = _DOC_HEADERS["providers"].splitlines(),
)

stardoc_with_diff_test(
    name = "rules",
    bzl_library_target = "//doc:doc",
    header_template = ":rules_header",
    symbol_names = _DOC_SYMBOLS["rules"],
)

write_file(
    name = "rules_header",
    out = "rules_header.vm",
    content = _DOC_HEADERS["rules"].splitlines(),
)

stardoc_with_diff_test(
    name = "setup",
    bzl_library_target = "//swift:repositories",
    header_template = ":setup_header",
)

write_file(
    name = "setup_header",
    out = "setup_header.vm",
    content = _DOC_HEADERS["setup"].splitlines(),
)

update_docs()

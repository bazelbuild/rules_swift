"""Tests for suppress_warning_groups."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
)
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")
load("//swift/internal:providers.bzl", "SwiftOverlayCompileInfo")

def suppress_warning_groups_test_suite(name, tags = []):
    """Test suite for suppress_warning_groups handling.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    action_command_line_test(
        name = "{}_swift_library_single".format(name),
        expected_argv = [
            "-Xwrapped-swift=-suppress-warning-group=DeprecatedDeclaration",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/suppress_warning_groups:single_category",
    )

    action_command_line_test(
        name = "{}_swift_library_multiple".format(name),
        expected_argv = [
            "-Xwrapped-swift=-suppress-warning-group=DeprecatedDeclaration",
            "-Xwrapped-swift=-suppress-warning-group=ImplementationOnlyDeprecated",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/suppress_warning_groups:multiple_categories",
    )

    overlay_copts_test(
        name = "{}_swift_overlay_copts".format(name),
        expected_copt = "-Xwrapped-swift=-suppress-warning-group=OverlayDeprecated",
        tags = all_tags,
        target_under_test = "//test/fixtures/suppress_warning_groups:overlay",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

def _normalize_copt(copt):
    if copt.startswith("\"") and copt.endswith("\""):
        return copt[1:-1]
    return copt

def _overlay_copts_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    if SwiftOverlayCompileInfo not in target_under_test:
        unittest.fail(
            env,
            "Target '{}' did not provide SwiftOverlayCompileInfo.".format(
                target_under_test.label,
            ),
        )
        return analysistest.end(env)

    actual = [
        _normalize_copt(copt)
        for copt in target_under_test[SwiftOverlayCompileInfo].copts
    ]
    expected = ctx.attr.expected_copt
    if expected not in actual:
        unittest.fail(
            env,
            ("Expected '{}' to contain '{}' in SwiftOverlayCompileInfo.copts, " +
             "but got {}.").format(
                target_under_test.label,
                expected,
                actual,
            ),
        )
    return analysistest.end(env)

overlay_copts_test = analysistest.make(
    _overlay_copts_test_impl,
    attrs = {
        "expected_copt": attr.string(
            mandatory = True,
            doc = "The compiler option expected in SwiftOverlayCompileInfo.copts.",
        ),
    },
)

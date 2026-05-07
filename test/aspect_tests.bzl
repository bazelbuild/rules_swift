"""Tests for `swift_clang_module_aspect`"""

load("@bazel_skylib//rules:build_test.bzl", "build_test")

def aspect_tests(name, tags = []):
    """Tests for `swift_clang_module_aspect`

    Args:
        name: The base name to be used for targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    build_test(
        name = "{}_build_test".format(name),
        tags = all_tags,
        targets = [
            "//test/fixtures/precompile_user_compile_flags:user_explicit_modules",
        ],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

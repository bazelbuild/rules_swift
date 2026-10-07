"""Tests for `swift_clang_module_aspect`"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:build_test.bzl", "build_test")

def _unique_outputs_test_impl(ctx):
    env = analysistest.begin(ctx)
    files = analysistest.target_under_test(env)[DefaultInfo].files.to_list()
    maps = [f.path for f in files if f.basename == "module.modulemap"]
    pcms = [f.path for f in files if f.extension == "pcm"]
    asserts.equals(env, 3, len(maps))
    asserts.equals(env, 3, len(pcms))
    asserts.equals(env, 1, len([p for p in maps if p.endswith("/module_modulemap/_/module.modulemap")]))
    asserts.equals(env, 1, len([p for p in pcms if p.endswith("/module.swift.pcm")]))
    return analysistest.end(env)

_unique_outputs_test = analysistest.make(_unique_outputs_test_impl)

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

    _unique_outputs_test(
        name = "{}_unique_outputs".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/aspect_outputs:outputs",
    )

    build_test(
        name = "{}_unique_outputs_build_test".format(name),
        tags = all_tags,
        targets = ["//test/fixtures/aspect_outputs:outputs"],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

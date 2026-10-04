"""Tests for `swift_clang_module_aspect`"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:build_test.bzl", "build_test")

def _aspect_outputs_test_impl(ctx):
    env = analysistest.begin(ctx)
    files = analysistest.target_under_test(env)[DefaultInfo].files.to_list()
    module_maps = [file for file in files if file.basename == "module.modulemap"]
    pcms = [file for file in files if file.extension == "pcm"]
    asserts.equals(env, 3, len({file.path: None for file in module_maps}), "Each aspect must have its own module map")
    asserts.equals(env, 3, len({file.path: None for file in pcms}), "Each aspect must have its own PCM")
    asserts.equals(env, 1, len([
        file
        for file in module_maps
        if file.path.endswith("/module_modulemap/_/module.modulemap")
    ]), "The default aspect must preserve its module map path")
    asserts.equals(env, 1, len([
        file
        for file in pcms
        if file.basename == "module.swift.pcm"
    ]), "The default aspect must preserve its PCM path")
    return analysistest.end(env)

aspect_outputs_test = analysistest.make(_aspect_outputs_test_impl)

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

    aspect_outputs_test(
        name = "{}_unique_outputs".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/aspect_outputs:outputs",
    )

    build_test(
        name = "{}_custom_aspects_build".format(name),
        tags = all_tags,
        targets = ["//test/fixtures/aspect_outputs:outputs"],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

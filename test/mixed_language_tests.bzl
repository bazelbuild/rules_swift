"""Tests for mixed_language_library."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:build_test.bzl", "build_test")

def _mixed_language_coverage_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    instrumented_files = sorted([
        file.short_path
        for file in target[InstrumentedFilesInfo].instrumented_files.to_list()
    ])

    asserts.equals(
        env,
        sorted(ctx.attr.expected_instrumented_files),
        instrumented_files,
    )

    return analysistest.end(env)

mixed_language_coverage_test = analysistest.make(
    _mixed_language_coverage_test_impl,
    attrs = {
        "expected_instrumented_files": attr.string_list(),
    },
    config_settings = {
        "//command_line_option:collect_code_coverage": "true",
    },
)

def mixed_language_test_suite(name, tags = []):
    all_tags = [name] + tags

    build_test(
        name = "{}_build_test".format(name),
        targets = ["//test/fixtures/mixed_language:MixedLibraryWithTestOnlyDeps"],
        tags = all_tags,
    )

    mixed_language_coverage_test(
        name = "{}_coverage_test".format(name),
        expected_instrumented_files = [
            "test/fixtures/mixed_language/MixedLibrary.h",
            "test/fixtures/mixed_language/MixedLibrary.m",
            "test/fixtures/mixed_language/MixedLibrary.swift",
            "test/fixtures/mixed_language/TestOnlyDep.h",
        ],
        target_under_test = "//test/fixtures/mixed_language:MixedLibraryWithTestOnlyDeps",
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

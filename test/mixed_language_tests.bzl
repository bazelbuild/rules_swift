"""Tests for mixed_language_library."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")

def mixed_language_test_suite(name, tags = []):
    all_tags = [name] + tags

    build_test(
        name = "{}_build_test".format(name),
        targets = ["//test/fixtures/mixed_language:MixedLibraryWithTestOnlyDeps"],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

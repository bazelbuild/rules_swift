# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0

"""Tests that `--features=swift.static_stdlib` actually links the Swift runtime statically."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//test/rules:static_stdlib_link_test.bzl", "with_static_stdlib")

def static_stdlib_test_suite(name, tags = []):
    """Verifies that binaries built with `swift.static_stdlib` are statically linked.

    Produces one `sh_test` (Linux-only) that inspects the linked ELF with
    `readelf -d` and asserts no Swift runtime libraries (`libswiftCore`,
    `libswift_Concurrency`, etc.) appear as `NEEDED` entries.

    Args:
        name: The base name for targets created by this macro.
        tags: Additional tags to apply to each target.
    """
    all_tags = [name] + tags

    with_static_stdlib(
        name = "{}_bin".format(name),
        tags = all_tags + ["manual"],
        target = "//test/fixtures/static_stdlib:bin",
    )

    sh_test(
        name = "{}_not_dynamically_linked".format(name),
        srcs = ["//test/rules:verify_static_stdlib.sh"],
        args = ["$(rootpath :{}_bin)".format(name)],
        data = [":{}_bin".format(name)],
        tags = all_tags,
        target_compatible_with = ["@platforms//os:linux"],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

"""Tests for `target_triples`."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//swift/internal:target_triples.bzl", "target_triples")

def _normalize_windows_vendor_test(ctx):
    env = unittest.begin(ctx)

    for cpu in ("x86_64", "aarch64"):
        triple = target_triples.make(
            cpu = cpu,
            vendor = "pc",
            os = "windows",
            environment = "msvc",
        )
        asserts.equals(
            env,
            cpu + "-unknown-windows-msvc",
            target_triples.str(target_triples.normalize_for_swift(triple)),
        )

    return unittest.end(env)

normalize_windows_vendor_test = unittest.make(_normalize_windows_vendor_test)

def target_triples_test_suite(name):
    return unittest.suite(
        name,
        normalize_windows_vendor_test,
    )

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

def _normalize_android_arm_test(ctx):
    env = unittest.begin(ctx)

    for triple, expected in (
        ("arm-unknown-linux-android21", "armv7-unknown-linux-android21"),
        ("arm-linux-androideabi", "armv7-linux-androideabi"),
        ("armv7a-unknown-linux-androideabi21", "armv7a-unknown-linux-androideabi21"),
        ("aarch64-unknown-linux-android28", "aarch64-unknown-linux-android28"),
        ("arm-unknown-linux-gnueabihf", "arm-unknown-linux-gnueabihf"),
    ):
        asserts.equals(
            env,
            expected,
            target_triples.str(target_triples.normalize_for_swift(target_triples.parse(triple))),
        )

    return unittest.end(env)

normalize_android_arm_test = unittest.make(_normalize_android_arm_test)

def target_triples_test_suite(name):
    return unittest.suite(
        name,
        normalize_windows_vendor_test,
        normalize_android_arm_test,
    )

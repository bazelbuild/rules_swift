load("//swift:swift_binary.bzl", "swift_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

licenses(["notice"])

package(
    default_visibility = ["//test:__subpackages__"],
)

# The platform the analysis tests transition the JNI library to. Its
# constraints (os:android + cpu:arm64, an alias of aarch64) resolve the Android
# Swift SDK toolchain and the Android cc toolchain.
platform(
    name = "android_arm64",
    constraint_values = [
        "@platforms//cpu:arm64",
        "@platforms//os:android",
    ],
)

# A JNI shared library built by the Android Swift SDK toolchain; the tests
# inspect its compile/link actions.
swift_binary(
    name = "jni_lib",
    srcs = ["jni.swift"],
    linkshared = True,
    tags = FIXTURE_TAGS,
)

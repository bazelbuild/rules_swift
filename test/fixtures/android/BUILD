load("@rules_android//rules:rules.bzl", "android_binary", "android_library")
load("@rules_cc//cc:defs.bzl", "cc_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

licenses(["notice"])

package(default_visibility = ["//test:__subpackages__"])

swift_binary(
    name = "jni_lib",
    srcs = ["jni.swift"],
    linkshared = True,
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "jni_lib_native",
    srcs = [":jni_lib"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:android"],
)

android_library(
    name = "app_lib",
    srcs = ["java/com/example/FixtureActivity.java"],
    custom_package = "com.example",
    manifest = "AndroidManifest.xml",
    tags = FIXTURE_TAGS,
)

android_binary(
    name = "app",
    manifest = "AndroidManifest.xml",
    tags = FIXTURE_TAGS,
    deps = [
        ":app_lib",
        ":jni_lib_native",
    ],
)

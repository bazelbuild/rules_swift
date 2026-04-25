load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures/precompiled_modules:force_features.bzl", "force_features_binary")
load(":extract_pcm.bzl", "extract_pcm")

force_features_binary(
    name = "foundation_pcm",
    binary = "@apple_sdk//:Foundation_clang",
    target_compatible_with = ["@platforms//os:macos"],
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
    ],
)

sh_test(
    name = "hermetic_pcm_test",
    srcs = ["check_hermetic_pcm.sh"],
    args = ["$(rootpath :foundation_pcm)"],
    data = [":foundation_pcm"],
)

swift_interop_hint(
    name = "SimpleObj_hint",
    module_name = "SimpleObj",
)

objc_library(
    name = "SimpleObj",
    srcs = ["SimpleObj.m"],
    hdrs = ["SimpleObj.h"],
    aspect_hints = [":SimpleObj_hint"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = ["@apple_sdk//:Foundation"],
)

extract_pcm(
    name = "simple_obj_pcm",
    target = ":SimpleObj",
)

sh_test(
    name = "hermetic_objc_pcm_test",
    srcs = ["check_hermetic_pcm.sh"],
    args = ["$(rootpath :simple_obj_pcm)"],
    data = [":simple_obj_pcm"],
)

swift_library(
    name = "SimpleSwift",
    srcs = ["SimpleSwift.swift"],
    generates_header = True,
    module_name = "SimpleSwift",
)

extract_pcm(
    name = "simple_swift_header_pcm",
    target = ":SimpleSwift",
    target_compatible_with = ["@platforms//os:macos"],
)

sh_test(
    name = "hermetic_swift_header_pcm_test",
    srcs = ["check_hermetic_pcm.sh"],
    args = ["$(rootpath :simple_swift_header_pcm)"],
    data = [":simple_swift_header_pcm"],
)

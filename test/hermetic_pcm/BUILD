load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//test/fixtures/precompiled_modules:force_features.bzl", "force_features_binary")

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

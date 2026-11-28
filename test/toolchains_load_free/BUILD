load("@bazel_skylib//rules:diff_test.bzl", "diff_test")

licenses(["notice"])

genquery(
    name = "toolchains_buildfiles",
    expression = "let t = //toolchains:toolchain_type in buildfiles($t) except filter('apple_support', buildfiles($t))",
    scope = ["//toolchains:toolchain_type"],
)

diff_test(
    name = "toolchains_load_free_test",
    size = "small",
    file1 = ":toolchains_buildfiles",
    file2 = "toolchains_buildfiles.golden",
)

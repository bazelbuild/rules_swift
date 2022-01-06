load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load(":cc_library_tests.bzl", "cc_library_test_suite")
load(":debug_settings_tests.bzl", "debug_settings_test_suite")
load(":generated_header_tests.bzl", "generated_header_test_suite")
load(":interop_hints_tests.bzl", "interop_hints_test_suite")
load(":private_deps_tests.bzl", "private_deps_test_suite")
load(":swift_through_non_swift_tests.bzl", "swift_through_non_swift_test_suite")

licenses(["notice"])

cc_library_test_suite(name = "cc_library")

debug_settings_test_suite(name = "debug_settings")

generated_header_test_suite(name = "generated_header")

interop_hints_test_suite(name = "interop_hints")

private_deps_test_suite(name = "private_deps")

swift_through_non_swift_test_suite(name = "swift_through_non_swift")

test_suite(
    name = "all_tests",
)

bzl_library(
    name = "starlark_tests_bzls",
    srcs = glob(["*.bzl"]),
    deps = [
        "//test/fixtures:starlark_tests_bzls",
        "//test/rules:starlark_tests_bzls",
        "@bazel_skylib//rules:build_test",
    ],
)

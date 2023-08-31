load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load(":cc_library_tests.bzl", "cc_library_test_suite")
load(":debug_settings_tests.bzl", "debug_settings_test_suite")
load(":generated_header_tests.bzl", "generated_header_test_suite")
load(":interop_hints_tests.bzl", "interop_hints_test_suite")
load(":module_interface_tests.bzl", "module_interface_test_suite")
load(":module_mapping_tests.bzl", "module_mapping_test_suite")
load(":private_deps_tests.bzl", "private_deps_test_suite")
load(":swift_through_non_swift_tests.bzl", "swift_through_non_swift_test_suite")
load(":symbol_graphs_tests.bzl", "symbol_graphs_test_suite")

licenses(["notice"])

cc_library_test_suite(
    name = "cc_library",
)

debug_settings_test_suite(
    name = "debug_settings",
)

generated_header_test_suite(
    name = "generated_header",
)

interop_hints_test_suite(
    name = "interop_hints",
)

module_interface_test_suite(
    name = "module_interface",
)

module_mapping_test_suite(
    name = "module_mapping",
)

private_deps_test_suite(
    name = "private_deps",
)

swift_through_non_swift_test_suite(
    name = "swift_through_non_swift",
)

symbol_graphs_test_suite(
    name = "symbol_graphs",
)

test_suite(
    name = "all_tests",
)

bzl_library(
    name = "starlark_tests_bzls",
    srcs = glob(["*.bzl"]),
    deps = [
        "//swift:swift_module_mapping_test",
        "//test/rules:starlark_tests_bzls",
        "@bazel_skylib//rules:build_test",
    ],
)

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load(":ast_file_tests.bzl", "ast_file_test_suite")
load(":bzl_test.bzl", "bzl_test")
load(":cc_library_tests.bzl", "cc_library_test_suite")
load(":compiler_arguments_tests.bzl", "compiler_arguments_test_suite")
load(":coverage_settings_tests.bzl", "coverage_settings_test_suite")
load(":debug_settings_tests.bzl", "debug_settings_test_suite")
load(":features_tests.bzl", "features_test_suite")
load(":generated_header_tests.bzl", "generated_header_test_suite")
load(":imported_framework_tests.bzl", "imported_framework_test_suite")
load(":interop_hints_tests.bzl", "interop_hints_test_suite")
load(":mainattr_tests.bzl", "mainattr_test_suite")
load(":module_cache_settings_tests.bzl", "module_cache_settings_test_suite")
load(":module_interface_tests.bzl", "module_interface_test_suite")
load(":output_file_map_tests.bzl", "output_file_map_test_suite")
load(":pch_output_dir_tests.bzl", "pch_output_dir_test_suite")
load(":private_deps_tests.bzl", "private_deps_test_suite")
load(":private_swiftinterface_tests.bzl", "private_swiftinterface_test_suite")
load(":split_derived_files_tests.bzl", "split_derived_files_test_suite")
load(":swift_through_non_swift_tests.bzl", "swift_through_non_swift_test_suite")
load(":utils_tests.bzl", "utils_test_suite")
load(":xctest_runner_tests.bzl", "xctest_runner_test_suite")
load(":swift_binary_linking_tests.bzl", "swift_binary_linking_test_suite")

licenses(["notice"])

ast_file_test_suite(name = "ast_file")

compiler_arguments_test_suite(name = "compiler_arguments")

cc_library_test_suite(name = "cc_library")

coverage_settings_test_suite(name = "coverage_settings")

debug_settings_test_suite(name = "debug_settings")

features_test_suite(name = "features")

generated_header_test_suite(name = "generated_header")

imported_framework_test_suite(name = "imported_framework")

mainattr_test_suite(name = "mainattr")

module_cache_settings_test_suite(name = "module_cache_settings")

output_file_map_test_suite(name = "output_file_map")

module_interface_test_suite(name = "module_interface")

interop_hints_test_suite()

private_deps_test_suite(name = "private_deps")

swift_through_non_swift_test_suite(name = "swift_through_non_swift")

split_derived_files_test_suite(name = "split_derived_files")

pch_output_dir_test_suite(name = "pch_output_dir_settings")

private_swiftinterface_test_suite(name = "private_swiftinterface")

xctest_runner_test_suite(name = "xctest_runner")

utils_test_suite(name = "utils")

swift_binary_linking_test_suite(name = "swift_binary_rules")

test_suite(
    name = "all_tests",
)

bzl_test(
    name = "swift_bzl_test",
    src = "swift_bzl_macro.bzl",
    deps = ["//swift"],
)

bzl_library(
    name = "swift_bzl_macro",
    srcs = ["swift_bzl_macro.bzl"],
    visibility = ["//visibility:private"],
    deps = ["//swift"],
)

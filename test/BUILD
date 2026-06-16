load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load(":additional_linker_inputs_tests.bzl", "additional_linker_inputs_test_suite")
load(":aspect_tests.bzl", "aspect_tests")
load(":ast_file_tests.bzl", "ast_file_test_suite")
load(":bzl_test.bzl", "bzl_test")
load(":cc_library_tests.bzl", "cc_library_test_suite")
load(":compiler_arguments_tests.bzl", "compiler_arguments_test_suite")
load(":const_values_tests.bzl", "const_values_test_suite")
load(":coverage_settings_tests.bzl", "coverage_settings_test_suite")
load(":debug_settings_tests.bzl", "debug_settings_test_suite")
load(":environment_tests.bzl", "environment_test_suite")
load(":features_tests.bzl", "features_test_suite")
load(":generated_header_tests.bzl", "generated_header_test_suite")
load(":imported_framework_tests.bzl", "imported_framework_test_suite")
load(":interop_hints_tests.bzl", "interop_hints_test_suite")
load(":layering_check_tests.bzl", "layering_check_test_suite")
load(":localized_strings_tests.bzl", "localized_strings_test_suite")
load(":mainattr_tests.bzl", "mainattr_test_suite")
load(":mixed_language_tests.bzl", "mixed_language_test_suite")
load(":module_cache_settings_tests.bzl", "module_cache_settings_test_suite")
load(":module_interface_tests.bzl", "module_interface_test_suite")
load(":module_mapping_tests.bzl", "module_mapping_test_suite")
load(":output_file_map_tests.bzl", "output_file_map_test_suite")
load(":pch_output_dir_tests.bzl", "pch_output_dir_test_suite")
load(":precompiled_modules_tests.bzl", "precompiled_modules_test_suite")
load(":private_deps_tests.bzl", "private_deps_test_suite")
load(":private_swiftinterface_tests.bzl", "private_swiftinterface_test_suite")
load(":runtime_deps_tests.bzl", "runtime_deps_test_suite")
load(":split_derived_files_tests.bzl", "split_derived_files_test_suite")
load(":swift_binary_linking_tests.bzl", "swift_binary_linking_test_suite")
load(":swift_through_non_swift_tests.bzl", "swift_through_non_swift_test_suite")
load(":swift_toolchain_tests.bzl", "swift_toolchain_test_suite")
load(":symbol_graphs_tests.bzl", "symbol_graphs_test_suite")
load(":synthesize_interface_tests.bzl", "synthesize_interface_test_suite")
load(":utils_tests.bzl", "utils_test_suite")
load(":xctest_runner_tests.bzl", "xctest_runner_test_suite")

licenses(["notice"])

additional_linker_inputs_test_suite(name = "additional_linker_inputs")

aspect_tests(name = "aspect_tests")

ast_file_test_suite(name = "ast_file")

cc_library_test_suite(name = "cc_library")

compiler_arguments_test_suite(name = "compiler_arguments")

const_values_test_suite(name = "const_values")

coverage_settings_test_suite(name = "coverage_settings")

debug_settings_test_suite(name = "debug_settings")

environment_test_suite(name = "environment")

features_test_suite(name = "features")

generated_header_test_suite(name = "generated_header")

imported_framework_test_suite(name = "imported_framework")

interop_hints_test_suite(name = "interop_hints")

layering_check_test_suite(name = "layering_check")

localized_strings_test_suite(name = "localized_strings")

mainattr_test_suite(name = "mainattr")

mixed_language_test_suite(name = "mixed_language")

module_cache_settings_test_suite(name = "module_cache_settings")

module_interface_test_suite(name = "module_interface")

module_mapping_test_suite(name = "module_mapping")

output_file_map_test_suite(name = "output_file_map")

private_deps_test_suite(name = "private_deps")

split_derived_files_test_suite(name = "split_derived_files")

swift_binary_linking_test_suite(name = "swift_binary_rules")

swift_through_non_swift_test_suite(name = "swift_through_non_swift")

swift_toolchain_test_suite(name = "swift_toolchain")

symbol_graphs_test_suite(name = "symbol_graphs")

synthesize_interface_test_suite(
    name = "synthesize_interface",
    # Don't run this on CI until Xcode 16.3 is available.
    tags = [
        "manual",
    ],
)

pch_output_dir_test_suite(name = "pch_output_dir_settings")

precompiled_modules_test_suite(name = "precompiled_modules")

private_swiftinterface_test_suite(name = "private_swiftinterface")

utils_test_suite(name = "utils")

xctest_runner_test_suite(name = "xctest_runner")

runtime_deps_test_suite(name = "runtime_deps")

test_suite(
    name = "all_tests",
)

bzl_test(
    name = "swift_bzl_test",
    src = "swift_bzl_macro.bzl",
    deps = ["//swift:providers"],
)

bool_flag(
    name = "apple_build_tests",
    build_setting_default = True,
)

config_setting(
    name = "apple_build_tests_enabled",
    flag_values = {":apple_build_tests": "True"},
    visibility = ["//visibility:public"],
)

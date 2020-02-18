load(":generated_header_tests.bzl", "generated_header_test_suite")
load(":private_deps_tests.bzl", "private_deps_test_suite")
load(":swift_through_non_swift_tests.bzl", "swift_through_non_swift_test_suite")

licenses(["notice"])

generated_header_test_suite()

private_deps_test_suite()

swift_through_non_swift_test_suite()

test_suite(
    name = "all_tests",
)

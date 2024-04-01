"""Tests for swift_binary's output path"""

load(
    "@build_bazel_rules_swift//test/rules:swift_binary_linking_test.bzl",
    "make_swift_binary_linking_test_rule",
    "swift_binary_linking_test",
)

swift_binary_linking_with_target_name_test = make_swift_binary_linking_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.add_target_name_to_output",
        ],
    },
)

def swift_binary_linking_test_suite(name):
    swift_binary_linking_with_target_name_test(
        name = "{}_with_target_name".format(name),
        output_binary_path = "test/fixtures/linking/bin/bin",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/linking:bin",
    )

    swift_binary_linking_test(
        name = "{}_default".format(name),
        output_binary_path = "test/fixtures/linking/bin",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/linking:bin",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )

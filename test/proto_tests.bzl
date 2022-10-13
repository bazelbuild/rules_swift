"""Tests for validating proto behavior"""

load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "make_provider_test_rule",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_protoc_gen_aspect.bzl",
    "swift_protoc_gen_aspect",
)

proto_provider_full_path_test = make_provider_test_rule(
    extra_target_under_test_aspects = [swift_protoc_gen_aspect],
)

proto_provider_path_to_underscores_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.generate_path_to_underscores_from_proto_files",
        ],
    },
    extra_target_under_test_aspects = [swift_protoc_gen_aspect],
)

def proto_test_suite(name):
    """Test suite for proto options.

    Args:
      name: the base name to be used in things created by this macro
    """

    proto_provider_full_path_test(
        name = "{}_full_path".format(name),
        expected_files = [
            "test/fixtures/proto/full_path_proto.protoc_gen_pb_swift/message_1.pb.swift",
            "test/fixtures/proto/full_path_proto.protoc_gen_pb_swift/message_2.pb.swift",
        ],
        field = "pbswift_files",
        provider = "SwiftProtoInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:full_path_proto",
    )

    proto_provider_path_to_underscores_test(
        name = "{}_path_to_underscores".format(name),
        expected_files = [
            "test/fixtures/proto/path_to_underscores_proto.protoc_gen_pb_swift/message_1_message.pb.swift",
            "test/fixtures/proto/path_to_underscores_proto.protoc_gen_pb_swift/message_2_message.pb.swift",
        ],
        field = "pbswift_files",
        provider = "SwiftProtoInfo",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:path_to_underscores_proto",
    )

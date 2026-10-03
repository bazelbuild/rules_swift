# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Tests for `swift_proto_library` and `swift_protoc_gen_aspect`."""

load(
    "@build_bazel_rules_swift//swift/internal:swift_protoc_gen_aspect.bzl",
    "swift_protoc_gen_aspect",
)
load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:analysis_failure_test.bzl",
    "make_analysis_failure_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

proto_aspect_action_command_line_test = make_action_command_line_test_rule(
    extra_target_under_test_aspects = [swift_protoc_gen_aspect],
)

disable_reflection_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "@build_bazel_rules_swift//swift:disable_proto_reflection": True,
    },
    extra_target_under_test_aspects = [swift_protoc_gen_aspect],
)

analysis_failure_test = make_analysis_failure_test_rule()

def proto_test_suite(name, tags = []):
    """Test suite for `swift_proto_library`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that `OutputGroupInfo.ide_srcs` exposes the generated `.pb.swift`
    # files.
    provider_test(
        name = "{}_ide_srcs_output_group".format(name),
        expected_files = [
            "leaf.pb.swift",
        ],
        field = "ide_srcs",
        provider = "OutputGroupInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:leaf_swift_proto",
    )

    # Verify that by default (`disable_proto_reflection = False`), neither
    # `ExperimentalHiddenNames=All` nor `-disable-reflection-metadata` is
    # passed.
    proto_aspect_action_command_line_test(
        name = "{}_default_protoc_flags".format(name),
        mnemonic = "ProtocGenSwift",
        not_expected_argv = [
            "--swift_opt=ExperimentalHiddenNames=All",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:leaf_proto",
    )

    proto_aspect_action_command_line_test(
        name = "{}_default_compile_flags".format(name),
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        not_expected_argv = [
            "-Xfrontend -disable-reflection-metadata",
            "-Xfrontend -disable-reflection-names",
        ],
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:leaf_proto",
    )

    # Verify that `--@build_bazel_rules_swift//swift:disable_proto_reflection`
    # passes `--swift_opt=ExperimentalHiddenNames=All` to `ProtocGenSwift` and
    # `-Xfrontend -disable-reflection-metadata -Xfrontend -disable-reflection-names`
    # to the Swift compilation action.
    disable_reflection_action_command_line_test(
        name = "{}_disable_reflection_protoc_flags".format(name),
        expected_argv = [
            "--swift_opt=ExperimentalHiddenNames=All",
        ],
        mnemonic = "ProtocGenSwift",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:leaf_proto",
    )

    disable_reflection_action_command_line_test(
        name = "{}_disable_reflection_compile_flags".format(name),
        expected_argv = [
            "-Xfrontend -disable-reflection-metadata",
            "-Xfrontend -disable-reflection-names",
        ],
        mnemonic = select({
            "@build_bazel_apple_support//constraints:apple": "SwiftCompile",
            "//conditions:default": "SwiftCompileModule",
        }),
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:leaf_proto",
    )

    # Verify that a collector `proto_library` without `srcs` in the transitive
    # `proto_library` graph propagates its `deps`' `SwiftInfo` modules to
    # downstream `proto_library` and `swift_proto_library` targets.
    provider_test(
        name = "{}_collector_proto_propagates_transitive_modules".format(name),
        expected_values = [
            "*",
            "third_party_bazel_rules_rules_swift_test_fixtures_proto_leaf_proto",
            "third_party_bazel_rules_rules_swift_test_fixtures_proto_top_proto",
        ],
        field = "transitive_modules.name",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:top_swift_proto",
    )

    # Verify that a `swift_proto_library` target that directly depends on a
    # `proto_library` without `srcs` fails analysis.
    analysis_failure_test(
        name = "{}_direct_collector_proto_fails".format(name),
        expected_message = "proto_library deps without srcs are not permitted",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/proto:invalid_collector_swift_proto",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

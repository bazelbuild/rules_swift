# Copyright 2020 The Bazel Authors. All rights reserved.
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

"""Tests for `swift_library.generated_header`."""

load(
    "//test/rules:provider_test.bzl",
    "provider_test",
)

def runtime_deps_test_suite(name, tags = []):
    """Test suite for `swift_binary` runtime deps.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    provider_test(
        name = "{}_swift_binary_runtime_deps".format(name),
        expected_files = [
            "test/fixtures/runtime_deps/transitive_data.txt",
            "*",
        ],
        field = "default_runfiles.files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/runtime_deps",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )

# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""A rule to collect the outputs of a `swift_library`.

This rule is used in tests to simulate "pre-built" artifacts without having to
check them in directly.
"""

load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_import.bzl", "swift_import")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(
    "//test/rules:swift_library_artifact_collector.bzl",
    "swift_library_artifact_collector",
)

package(
    default_testonly = True,
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_binary(
    name = "client",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
    deps = [":private_swiftinterface_import"],
)

swift_import(
    name = "private_swiftinterface_import",
    archives = [":private_swiftinterface_outputs/libPrivateSwiftInterface.a"],
    module_name = "PrivateSwiftInterface",
    swiftdoc = ":private_swiftinterface_outputs/PrivateSwiftInterface.swiftdoc",
    # Using the private interface allows using both the normal and private interfaces of a module.
    # Only one swiftinterface is allowed per module, so we can't use both at the same time.
    # This tests that using the private interface allows a dependent module to use an `@_spi` symbol.
    swiftinterface = ":private_swiftinterface_outputs/PrivateSwiftInterface.private.swiftinterface",
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "private_swiftinterface",
    srcs = ["Lib.swift"],
    module_name = "PrivateSwiftInterface",
    tags = FIXTURE_TAGS,
)

swift_library_artifact_collector(
    name = "private_swiftinterface_artifact_collector",
    private_swiftinterface = "private_swiftinterface_outputs/PrivateSwiftInterface.private.swiftinterface",
    static_library = "private_swiftinterface_outputs/libPrivateSwiftInterface.a",
    swiftdoc = "private_swiftinterface_outputs/PrivateSwiftInterface.swiftdoc",
    swiftinterface = "private_swiftinterface_outputs/PrivateSwiftInterface.swiftinterface",
    tags = FIXTURE_TAGS,
    target = ":private_swiftinterface",
    target_compatible_with = ["@platforms//os:macos"],
)

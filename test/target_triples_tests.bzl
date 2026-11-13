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

"""Unit tests for `target_triples.bzl`."""

load(
    "@bazel_skylib//lib:unittest.bzl",
    "asserts",
    "unittest",
)
load(
    "@build_bazel_rules_swift//swift/internal:target_triples.bzl",
    "target_triples",
)

visibility("private")

def _parse_two_component_triple_test_impl(ctx):
    env = unittest.begin(ctx)
    wasip2 = target_triples.parse("wasm32-wasip2")
    asserts.equals(env, "wasm32", wasip2.cpu)
    asserts.equals(env, "unknown", wasip2.vendor)
    asserts.equals(env, "wasip2", wasip2.os)
    asserts.equals(env, None, wasip2.environment)
    asserts.equals(env, "wasm32-unknown-wasip2", target_triples.str(wasip2))
    asserts.equals(env, "wasip2", target_triples.unversioned_os(wasip2))
    asserts.equals(
        env,
        "wasip2",
        target_triples.platform_name_for_swift(wasip2),
    )

    wasip1 = target_triples.parse("wasm32-wasip1")
    asserts.equals(env, "wasip1", target_triples.unversioned_os(wasip1))
    asserts.equals(
        env,
        "wasi",
        target_triples.platform_name_for_swift(wasip1),
    )
    return unittest.end(env)

def _parse_three_and_four_component_triples_test_impl(ctx):
    env = unittest.begin(ctx)

    emscripten = target_triples.parse("wasm32-unknown-emscripten")
    asserts.equals(env, "wasm32", emscripten.cpu)
    asserts.equals(env, "unknown", emscripten.vendor)
    asserts.equals(env, "emscripten", emscripten.os)
    asserts.equals(env, None, emscripten.environment)
    asserts.equals(
        env,
        "emscripten",
        target_triples.platform_name_for_swift(emscripten),
    )

    ios = target_triples.parse("arm64-apple-ios17.2")
    asserts.equals(env, "ios", target_triples.unversioned_os(ios))
    asserts.equals(env, "iphoneos", target_triples.platform_name_for_swift(ios))

    win32 = target_triples.parse("x86_64-pc-win32-msvc")
    asserts.equals(env, "win32", target_triples.unversioned_os(win32))

    linux_gnu = target_triples.parse("x86_64-unknown-linux-gnu")
    asserts.equals(env, "x86_64", linux_gnu.cpu)
    asserts.equals(env, "unknown", linux_gnu.vendor)
    asserts.equals(env, "linux", linux_gnu.os)
    asserts.equals(env, "gnu", linux_gnu.environment)

    return unittest.end(env)

_parse_two_component_triple_test = unittest.make(
    _parse_two_component_triple_test_impl,
)
_parse_three_and_four_component_triples_test = unittest.make(
    _parse_three_and_four_component_triples_test_impl,
)

def target_triples_test_suite(name):
    """Test suite for `target_triples.bzl`.

    Args:
        name: The base name to be prefixed to things created by this macro.
    """
    _parse_two_component_triple_test(
        name = "{}_parse_two_component_triple_test".format(name),
    )
    _parse_three_and_four_component_triples_test(
        name = "{}_parse_three_and_four_component_triples_test".format(name),
    )

    native.test_suite(
        name = name,
        tests = [
            ":{}_parse_two_component_triple_test".format(name),
            ":{}_parse_three_and_four_component_triples_test".format(name),
        ],
    )

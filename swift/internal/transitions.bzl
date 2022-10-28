# Copyright 2022 The Bazel Authors. All rights reserved.
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

"""Transition support."""

def _proto_compiler_transition_impl(settings, _attr):
    # Change --proto_compiler option to point to our wrapper, so that we can
    # configure it to the universal binary when needed. However, respect
    # user-provided option if user provides their own compiler.
    if str(settings["//command_line_option:proto_compiler"]) not in [
        "@bazel_tools//tools/proto:protoc",
        "@com_google_protobuf//:protoc",
    ]:
        return settings

    return {"//command_line_option:proto_compiler": Label("//tools/protoc_wrapper:protoc")}

proto_compiler_transition = transition(
    implementation = _proto_compiler_transition_impl,
    inputs = ["//command_line_option:proto_compiler"],
    outputs = ["//command_line_option:proto_compiler"],
)

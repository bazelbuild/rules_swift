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

"""Re-exports of API symbols for stardoc."""

load(
    "//swift:module_name.bzl",
    _derive_swift_module_name = "derive_swift_module_name",
)
load("//swift:swift_common.bzl", _swift_common = "swift_common")
load(
    "//swift:swift_interop_info.bzl",
    _create_swift_interop_info = "create_swift_interop_info",
)
load(
    "//swift:swift_overlay_helpers.bzl",
    _is_swift_overlay = "is_swift_overlay",
)

create_swift_interop_info = _create_swift_interop_info
derive_swift_module_name = _derive_swift_module_name
is_swift_overlay = _is_swift_overlay
swift_common = _swift_common

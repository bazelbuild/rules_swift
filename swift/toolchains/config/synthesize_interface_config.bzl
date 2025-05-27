# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""Common configuration for interface synthesis actions."""

load(
    "//swift/internal:action_names.bzl",
    "SWIFT_ACTION_SYNTHESIZE_INTERFACE",
)
load(":action_config.bzl", "ActionConfigInfo", "add_arg")

def synthesize_interface_action_configs():
    """Returns the list of action configs needed to synthesize Swift interfaces.

    If a toolchain supports interface synthesis, it should add these to its
    list of action configs so that those actions will be correctly configured.
    (Other required configuration is provided by `compile_action_configs`.)

    Returns:
        The list of action configs needed to synthesize Swift interfaces.
    """
    return [
        ActionConfigInfo(
            actions = [SWIFT_ACTION_SYNTHESIZE_INTERFACE],
            configurators = [
                add_arg("-include-submodules"),
                add_arg("-print-fully-qualified-types"),
            ],
        ),
        ActionConfigInfo(
            actions = [SWIFT_ACTION_SYNTHESIZE_INTERFACE],
            configurators = [_synthesized_interface_output_configurator],
        ),
    ]

def _synthesized_interface_output_configurator(prerequisites, args):
    """Configures the outputs of the synthesize interface action."""
    args.add("-o", prerequisites.output_file)

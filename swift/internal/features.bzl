# Copyright 2018 The Bazel Authors. All rights reserved.
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

"""Helper functions for working with Bazel features."""

def is_feature_enabled(feature, feature_configuration):
    """Returns a value indicating whether the given feature is enabled.

    This function scans the user-provided feature lists with those defined by the toolchain.
    User-provided features always take precedence, so the user can force-enable a feature `"foo"`
    that has been disabled by default by the toolchain if they explicitly write `features = ["foo"]`
    in their target/package or pass `--features=foo` on the command line. Likewise, the user can
    force-disable a feature `"foo"` that has been enabled by default by the toolchain if they
    explicitly write `features = ["-foo"]` in their target/package or pass `--features=-foo` on the
    command line.

    If a feature is present in both the `features` and `disabled_features` lists, then disabling
    takes precedence. Bazel should prevent this case from ever occurring when it evaluates the set
    of features to pass to the rule context, however.

    Args:
        feature: The feature to be tested.
        feature_configuration: A value returned by `swift_common.configure_features` that specifies
            the enabled and disabled features of a particular target.

    Returns:
        `True` if the feature is explicitly enabled, or `False` if it is either explicitly disabled
        or not found in any of the feature lists.
    """
    if feature in feature_configuration.unsupported_features:
        return False
    if feature in feature_configuration.requested_features:
        return True
    if feature in feature_configuration.toolchain.unsupported_features:
        return False
    if feature in feature_configuration.toolchain.requested_features:
        return True
    return False

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

# We use the following constants within the rule definitions to prevent the possibility of typos
# when referring to them as part of the implementation, but we explicitly do not export them since
# it's not a common practice to use them that way in BUILD files; the expectation is that the actual
# string literals would be used there. (There is also no good way to generate documentation yet for
# constants since they don't have "doc" attributes, so exposing them in a more structured way
# doesn't provide a benefit there either.)

# If enabled, `swift-autolink-extract` will be invoked on the object files generated for a library
# or binary, generating a response file that will be passed automatically to the linker containing
# the libraries corresponding to modules that were imported. This is used to simulate the
# autolinking behavior of Mach-O on platforms with different binary formats.
SWIFT_FEATURE_AUTOLINK_EXTRACT = "swift.autolink_extract"

# If enabled, debug builds will use the `-debug-prefix-map` feature to remap the current working
# directory to `.`, which permits debugging remote or sandboxed builds.
SWIFT_FEATURE_DEBUG_PREFIX_MAP = "swift.debug_prefix_map"

# If enabled, the compilation action for a target will produce an index store.
SWIFT_FEATURE_INDEX_WHILE_BUILDING = "swift.index_while_building"

# If enabled, compilation actions and module map generation will assume that the header paths in
# module maps are relative to the current working directory (i.e., the workspace root); if disabled,
# header paths in module maps are relative to the location of the module map file.
SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD = "swift.module_map_home_is_cwd"

# If enabled, the compilation action for a library target will not generate an Objective-C header
# for the module. This feature also implies `swift.no_generated_module_map`.
SWIFT_FEATURE_NO_GENERATED_HEADER = "swift.no_generated_header"

# If enabled, the compilation action for a library target will not generate a module map for the
# Objective-C generated header. This feature is ignored if `swift.no_generated_header` is not
# present.
SWIFT_FEATURE_NO_GENERATED_MODULE_MAP = "swift.no_generated_module_map"

# If enabled, actions invoking the Swift driver or frontend may write argument lists into response
# files (i.e., "@args.txt") to avoid passing command lines that exceed the system limit. Toolchains
# typically set this automatically if using a sufficiently recent version of Swift (4.2 or higher).
SWIFT_FEATURE_USE_RESPONSE_FILES = "swift.use_response_files"

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

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

"""The global module name derivation algorithm used by rules_swift."""

load("@bazel_skylib//lib:types.bzl", "types")
load(
    "@build_bazel_rules_swift//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_LABEL_AS_MODULE_NAME",
)
load(
    "@build_bazel_rules_swift//swift/internal:features.bzl",
    "is_feature_enabled",
)

visibility("public")

def derive_swift_module_name(
        *args,
        feature_configuration = None):  # @unused
    """Returns a derived module name from the given build label.

    For targets whose module name is not explicitly specified, the module name
    is computed using the following algorithm:

    *   The package and name components of the label are considered separately.
        All _interior_ sequences of non-identifier characters (anything other
        than `a-z`, `A-Z`, `0-9`, and `_`) are replaced by a single underscore
        (`_`). Any leading or trailing non-identifier characters are dropped.
    *   If the package component is non-empty after the above transformation,
        it is joined with the transformed name component using an underscore.
        Otherwise, the transformed name is used by itself.
    *   If this would result in a string that begins with a digit (`0-9`), an
        underscore is prepended to make it identifier-safe.

    This mapping is intended to be fairly predictable, but not reversible.

    Args:
        *args: Either a single argument of type `Label`, or two arguments of
            type `str` where the first argument is the package name and the
            second argument is the target name.
        feature_configuration: The Swift feature configuration being used when
            compiling the target.

    Returns:
        The module name derived from the label.
    """
    if (len(args) == 1 and
        hasattr(args[0], "package") and
        hasattr(args[0], "name")):
        label = args[0]
        package = label.package
        name = label.name
    elif (len(args) == 2 and
          types.is_string(args[0]) and
          types.is_string(args[1])):
        package = args[0]
        name = args[1]
    else:
        fail("derive_module_name may only be called with a single argument " +
             "of type 'Label' or two arguments of type 'str'.")

    # If we have a feature configuration and the label-as-module-name feature is
    # enabled, use the label itself as the module name (canonicalized so that
    # it uses the short form when the last package component matches the name).
    if feature_configuration and is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_LABEL_AS_MODULE_NAME,
    ):
        if "=" in package or "=" in name:
            fail("Swift-compatible target labels may not contain '='.")

        if not package.startswith("//"):
            package = "//{}".format(package)
        if package.endswith("/{}".format(name)):
            return package
        return "{}:{}".format(package, name)

    package_part = _module_name_safe(package.lstrip("//"))
    name_part = _module_name_safe(name)
    if package_part:
        module_name = package_part + "_" + name_part
    else:
        module_name = name_part
    if module_name[0].isdigit():
        module_name = "_" + module_name
    return module_name

def physical_swift_module_name(module_name):
    """Returns the physical module name from the source name of a module.

    The "source name" is the alias of the module as it appears in source code,
    which may be the actual Bazel target label (when the
    `swift.label_as_module_name` feature is enabled in Swift 6.2 or later). It
    is a module alias for the "physical name", which is the identifier-safe name
    of the module that is used for its file system artifacts and its ABI.

    Args:
        module_name: The source name of the module.

    Returns:
        The physical module name.
    """
    if _is_valid_non_raw_identifier(module_name):
        return module_name

    if module_name.startswith("//"):
        # If the module name looks like a Bazel label, we need to transform it
        # a bit to maintain compatibility with legacy module names (because we
        # don't want the physical names to change for existing targets). This
        # means turning the short form (`//foo/bar`) back into the long form
        # (`//foo/bar:bar`) so that the physical name becomes `foo_bar_bar`
        # rather than `foo_bar`.
        if ":" not in module_name:
            module_name += ":{}".format(module_name.rsplit("/", 1))
        module_name = _module_name_safe(module_name.lstrip("//"))
    else:
        # If the user has provided a module name that doesn't look like a Bazel
        # label but still needs to be made identifier-safe, do that here without
        # any other special treatment.
        module_name = _module_name_safe(module_name)

    if module_name[0].isdigit():
        module_name = "_" + module_name
    return module_name

def _is_valid_non_raw_identifier(str):
    """Returns whether the given string is a valid non-raw identifier.

    We choose to ignore the vast set of Unicode code points that are supported
    as Swift identifiers, focusing only on ASCII characters that are going to
    appear in module names.
    """
    first = str[0]
    if first != "_" and not first.isalpha():
        return False
    for ch in str.elems()[1:]:
        if not ch.isalnum():
            return False
    return True

def _module_name_safe(string):
    """Returns a transformation of `string` that is safe for module names."""
    result = ""
    saw_non_identifier_char = False
    for ch in string.elems():
        if ch.isalnum() or ch == "_":
            # If we're seeing an identifier character after a sequence of
            # non-identifier characters, append an underscore and reset our
            # tracking state before appending the identifier character.
            if saw_non_identifier_char:
                result += "_"
                saw_non_identifier_char = False
            result += ch
        elif result:
            # Only track this if `result` has content; this ensures that we
            # (intentionally) drop leading non-identifier characters instead of
            # adding a leading underscore.
            saw_non_identifier_char = True

    return result

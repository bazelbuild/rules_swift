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

"""Unit test helpers for Starlark analysis tests.

This contains various helpers for dealing with collections and file expectations.
"""

load("@bazel_skylib//lib:types.bzl", "types")
load(
    "@bazel_skylib//lib:unittest.bzl",
    "asserts",
    "unittest",
)

visibility([
    "@build_bazel_rules_swift//test/...",
])

def _prettify(object):
    """Returns a prettified version of the given value for failure messages.

    If the object is a list, it will be formatted as a multiline string;
    otherwise, it will simply be the `repr` of the value.

    Args:
        object: The object to prettify.

    Returns:
        A string that can be used to display the value in a failure message.
    """
    object = normalize_collection(object)
    if types.is_list(object):
        return ("[\n    " +
                ",\n    ".join([repr(item) for item in object]) +
                "\n]")
    else:
        return repr(object)

def normalize_collection(object):
    """Returns object as a list if it is a collection, otherwise returns itself.

    Args:
        object: The object to normalize. If it is a list or a depset, it will be
            returned as a list. Otherwise, it will be returned unchanged.

    Returns:
        A list containing the same items in `object` if it is a collection,
        otherwise the original object is returned.
    """
    if types.is_depset(object):
        return object.to_list()
    elif types.is_dict(object):
        return ["{}={}".format(k, v) for k, v in object.items()]
    else:
        return object

def compare_expected_files(env, access_description, expected, actual):
    """Implements the `expected_files` comparison.

    This compares a set of files retrieved from a provider field against a list
    of expected strings that are equal to or suffixes of the paths to those
    files, as well as excluded files and a wildcard. See the documentation of
    the `expected_files` attribute on the rule definition below for specifics.

    Args:
        env: The analysis test environment.
        access_description: A target/provider/field access description string
            printed in assertion failure messages.
        expected: The list of expected file path inclusions/exclusions.
        actual: The collection of files obtained from the provider.
    """
    actual = normalize_collection(actual)

    if (
        not types.is_list(actual) or
        any([type(item) != "File" for item in actual])
    ):
        unittest.fail(
            env,
            ("Expected '{}' to be a collection of files, " +
             "but got a {}: {}.").format(
                access_description,
                type(actual),
                _prettify(actual),
            ),
        )
        return

    remaining = list(actual)

    expected_is_subset = "*" in expected
    expected_include = [
        s
        for s in expected
        if not s.startswith("-") and s != "*"
    ]
    expected_exclude = [s[1:] for s in expected if s.startswith("-")]

    # For every expected file, pick off the first actual that we find that has
    # the expected string as a suffix.
    failed = False
    for suffix in expected_include:
        if not remaining:
            # It's a failure if we are still expecting files but there are no
            # more actual files.
            failed = True
            break

        found_expected_file = False
        for i in range(len(remaining)):
            actual_path = remaining[i].path
            if actual_path.endswith(suffix):
                found_expected_file = True
                remaining.pop(i)
                break

        # It's a failure if we never found a file we expected.
        if not found_expected_file:
            failed = True
            break

    # For every file expected to *not* be present, check the list of remaining
    # files and fail if we find a match.
    for suffix in expected_exclude:
        for f in remaining:
            if f.path.endswith(suffix):
                failed = True
                break

    # If we found all the expected files, the remaining list should be empty.
    # Fail if the list is not empty and we're not looking for a subset.
    if not expected_is_subset and remaining:
        failed = True

    asserts.false(
        env,
        failed,
        "Expected '{}' to match {}, but got {}.".format(
            access_description,
            _prettify(expected),
            _prettify([
                f.path if type(f) == "File" else repr(f)
                for f in actual
            ]),
        ),
    )

def compare_expected_strings(env, access_description, expected, actual):
    """Implements the `expected_strings` comparison.

    This compares a list or dictionary of strings retrieved from a provider
    field against a list of expected strings, as well as excluded strings and a
    wildcard. See the documentation of the `expected_values` attribute on the
    rule definition below for specifics.

    Args:
        env: The analysis test environment.
        access_description: A target/provider/field access description string
            printed in assertion failure messages.
        expected: The list of expected string inclusions/exclusions.
        actual: The collection of strings obtained from the provider.
    """
    if not (types.is_list(actual) or types.is_dict(actual)):
        unittest.fail(
            env,
            ("Expected '{}' to be a list or dict of strings, " +
             "but got a {}: {}.").format(
                access_description,
                type(actual),
                _prettify(actual),
            ),
        )
        return

    actual = normalize_collection(actual)
    remaining = list(actual)

    expected_is_subset = "*" in expected
    expected_include = [
        s
        for s in expected
        if not s.startswith("-") and s != "*"
    ]
    expected_exclude = [s[1:] for s in expected if s.startswith("-")]

    # For every expected string, pick off the first actual that we find that is
    # equal to it.
    failed = False
    for current in expected_include:
        if not remaining:
            # It's a failure if we are still expecting strings but there are no
            # more actual strings.
            failed = True
            break

        found_expected_string = False
        for i in range(len(remaining)):
            actual_string = remaining[i]
            if actual_string == current:
                found_expected_string = True
                remaining.pop(i)
                break

        # It's a failure if we never found a string we expected.
        if not found_expected_string:
            failed = True
            break

    # For every string expected to *not* be present, check the list of remaining
    # strings and fail if we find a match.
    for current in expected_exclude:
        for r in remaining:
            if r == current:
                failed = True
                break

    # If we found all the expected strings, the remaining list should be empty.
    # Fail if the list is not empty and we're not looking for a subset.
    if not expected_is_subset and remaining:
        failed = True

    asserts.false(
        env,
        failed,
        "Expected '{}' to match {}, but got {}.".format(
            access_description,
            _prettify(expected),
            _prettify([repr(v) for v in actual]),
        ),
    )

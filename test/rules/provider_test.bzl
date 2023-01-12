# Copyright 2019 The Bazel Authors. All rights reserved.
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

"""Rules for testing the providers of a target under test."""

load("@build_bazel_rules_swift//swift:swift.bzl", "SwiftInfo")
load("@bazel_skylib//lib:types.bzl", "types")
load(
    "@bazel_skylib//lib:unittest.bzl",
    "analysistest",
    "asserts",
    "unittest",
)

# A sentinel value returned by `_evaluate_field` when a `None` value is
# encountered during the evaluation of a dotted path on any component other than
# the last component. This allows the caller to distinguish between a legitimate
# `None` value being returned by the entire path vs. an unexpected `None` in an
# earlier component.
#
# A `provider` is used here because it is a simple way of getting a known unique
# object from Bazel that cannot be equal to any other object.
_EVALUATE_FIELD_FAILED = provider(
    doc = "Sentinel value, not otherwise used.",
    fields = {},
)

def _evaluate_field(env, source, field):
    """Evaluates a field or field path on an object and returns its value.

    This function projects across collections. That is, if the result of
    evaluating a field along the path is a depset or a list, then the result
    will be normalized into a list and remaining fields in the path will be
    evaluated on every item in that list, not on the list itself.

    If a field path component in a projected collection is followed by an
    exclamation point, then this indicates that any `None` values produced at
    that stage of evaluation should be removed from the list before continuing.
    If evaluating the path fails because a `None` value is encountered anywhere
    before the last component and they are not filtered out, then an assertion
    failure is logged and the special value `EVALUATE_FIELD_FAILED` is returned.
    This value lets the caller short-circuit additional test logic that may not
    be relevant if evaluation is known to have failed.

    Args:
        env: The analysis test environment.
        source: The source object on which to evaluate the field or field path.
        field: The field or field path to evaluate. This can be a simple field
            name or a dotted path.

    Returns:
        The result of evaluating the field or field path on the source object.
        If a `None` value was encountered during evaluation of a field path
        component that was not the final component, then the special value
        `_EVALUATE_FIELD_FAILED` is returned.
    """
    components = field.split(".")

    for component in components:
        source = _normalize_collection(source)
        filter_nones = component.endswith("!")
        if filter_nones:
            component = component[:-1]

        if types.is_list(source):
            if any([item == None for item in source]):
                unittest.fail(
                    env,
                    "Got 'None' evaluating '{}' on an element in '{}'.".format(
                        component,
                        field,
                    ),
                )
                return _EVALUATE_FIELD_FAILED

            # If the elements are lists or depsets, flatten the whole thing into
            # a single list.
            flattened = []
            for item in source:
                item = _normalize_collection(item)
                if types.is_list(item):
                    flattened.extend(item)
                else:
                    flattened.append(item)
            source = [getattr(item, component, None) for item in flattened]
            if filter_nones:
                source = [item for item in source if item != None]
        else:
            if source == None:
                unittest.fail(
                    env,
                    "Got 'None' evaluating '{}' in '{}'.".format(
                        component,
                        field,
                    ),
                )
                return _EVALUATE_FIELD_FAILED

            source = getattr(source, component, None)
            if filter_nones:
                source = _normalize_collection(source)
                if types.is_list(source):
                    source = [item for item in source if item != None]
                else:
                    unittest.fail(
                        env,
                        ("Expected to filter 'None' values evaluating '{}' " +
                         "on an element in '{}', but the result was not a " +
                         "collection.").format(component, field),
                    )
                    return _EVALUATE_FIELD_FAILED

    return source

def _lookup_provider_by_name(env, target, provider_name):
    """Returns a provider on a target, given its name.

    The `provider_test` rule needs to be able to specify which provider a field
    should be looked up on, but it can't take provider objects directly as
    attribute values, so we have to use strings and a fixed lookup table to find
    them.

    If the provider is not recognized or is not propagated by the target, then
    an assertion failure is logged and `None` is returned. This lets the caller
    short-circuit additional test logic that may not be relevant if the provider
    is not present.

    Args:
        env: The analysis test environment.
        target: The target whose provider should be looked up.
        provider_name: The name of the provider to return.

    Returns:
        The provider value, or `None` if it was not propagated by the target.
    """
    provider = None
    if provider_name == "CcInfo":
        provider = CcInfo
    elif provider_name == "DefaultInfo":
        provider = DefaultInfo
    elif provider_name == "OutputGroupInfo":
        provider = OutputGroupInfo
    elif provider_name == "SwiftInfo":
        provider = SwiftInfo
    elif provider_name == "apple_common.Objc":
        provider = apple_common.Objc

    if not provider:
        unittest.fail(
            env,
            "Provider '{}' is not supported.".format(provider_name),
        )
        return None

    if provider in target:
        return target[provider]

    unittest.fail(
        env,
        "Target '{}' did not provide '{}'.".format(target.label, provider_name),
    )
    return None

def _field_access_description(target, provider, field):
    """Returns a string denoting field access to a provider on a target.

    This function is used to generate a pretty string that can be used in
    assertion failure messages, of the form
    `<//package:target>[ProviderInfo].some.field.path`.

    Args:
        target: The target whose provider is being accessed.
        provider: The name of the provider being accessed.
        field: The field name or dotted field path being accessed.

    Returns:
        A string describing the field access that can be used in assertion
        failure messages.
    """
    return "<{}>[{}].{}".format(target.label, provider, field)

def _prettify(object):
    """Returns a prettified version of the given value for failure messages.

    If the object is a list, it will be formatted as a multiline string;
    otherwise, it will simply be the `repr` of the value.

    Args:
        object: The object to prettify.

    Returns:
        A string that can be used to display the value in a failure message.
    """
    object = _normalize_collection(object)
    if types.is_list(object):
        return ("[\n    " +
                ",\n    ".join([repr(item) for item in object]) +
                "\n]")
    else:
        return repr(object)

def _normalize_collection(object):
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
    else:
        return object

def _compare_expected_files(env, access_description, expected, actual):
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
    actual = _normalize_collection(actual)

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

def _provider_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = ctx.attr.target_under_test

    # If configuration settings were provided, then we have a transition and
    # target_under_test will be a list. In that case, get the actual target by
    # pulling the first one out.
    if types.is_list(target_under_test):
        target_under_test = target_under_test[0]

    provider_name = ctx.attr.provider
    provider = _lookup_provider_by_name(env, target_under_test, provider_name)
    if not provider:
        return analysistest.end(env)

    field = ctx.attr.field
    actual = _evaluate_field(env, provider, field)
    if actual == _EVALUATE_FIELD_FAILED:
        return analysistest.end(env)

    access_description = _field_access_description(
        target_under_test,
        provider_name,
        field,
    )

    # TODO(allevato): Support other comparisons as they become needed.
    if ctx.attr.expected_files:
        _compare_expected_files(
            env,
            access_description,
            ctx.attr.expected_files,
            actual,
        )

    return analysistest.end(env)

def make_provider_test_rule(config_settings = {}):
    """Returns a new `provider_test`-like rule with custom config settings.

    Args:
        config_settings: A dictionary of configuration settings and their values
            that should be applied during tests.

    Returns:
        A rule returned by `analysistest.make` that has the `provider_test`
        interface and the given config settings.
    """
    return analysistest.make(
        _provider_test_impl,
        attrs = {
            "expected_files": attr.string_list(
                mandatory = False,
                doc = """\
The expected list of files when evaluating the given provider's field.

This list can contain three types of strings:

*   A path suffix (`foo/bar/baz.ext`), denoting that a file whose path has the
    given suffix must be present.
*   A negated path suffix (`-foo/bar/baz.ext`), denoting that a file whose path
    has the given suffix must *not* be present.
*   A wildcard (`*`), denoting that the expected list of files can be a *subset*
    of the actual list. If the wildcard is omitted, the expected list of files
    must match the actual list completely; unmatched files will result in a test
    failure.

The use of path suffixes allows the test to be unconcerned about specific
configuration details, such as output directories for generated files.
""",
            ),
            "field": attr.string(
                mandatory = True,
                doc = """\
The field name or dotted field path of the provider that should be tested.

Evaluation of field path components is projected across collections. That is, if
the result of evaluating a field along the path is a depset or a list, then the
result will be normalized into a list and remaining fields in the path will be
evaluated on every item in that list, not on the list itself. Likewise, if such
a field path component is followed by `!`, then any `None` elements that may
have resulted during evaluation will be removed from the list before evaluating
the next component.
""",
            ),
            "provider": attr.string(
                mandatory = True,
                doc = """\
The name of the provider expected to be propagated by the target under test, and
on which the field will be checked.

Currently, only the following providers are recognized:

*   `CcInfo`
*   `DefaultInfo`
*   `OutputGroupInfo`
*   `SwiftInfo`
*   `apple_common.Objc`
""",
            ),
        },
        config_settings = config_settings,
    )

# A default instantiation of the rule when no custom config settings are needed.
provider_test = make_provider_test_rule()

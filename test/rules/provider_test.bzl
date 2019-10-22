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
)

# A sentinel value returned by `_evaluate_field` when a `None` value is
# encountered during the evaluation of a dotted path on any component other than
# the last component. This allows the caller to distinguish between a legitimate
# `None` value being returned by the entire path vs. an unexpected `None` in an
# earlier component.
#
# A `provider` is used here because it is a simple way of getting a known unique
# object from Bazel that cannot be equal to any other object.
_EVALUATE_FIELD_FAILED = provider()

def _evaluate_field(env, source, field):
    """Evaluates a field or field path on an object and returns its value.

    If evaluating the path fails because a `None` value is encountered anywhere
    before the last component, an assertion failure is logged and the special
    value `EVALUATE_FIELD_FAILED` is returned. This value lets the caller
    short-circuit additional test logic that may not be relevant if evaluation
    is known to have failed.

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
        if source == None:
            asserts.expect_failure(
                env,
                "Got 'None' evaluating '{}' in '{}'.".format(component, field),
            )
            return _EVALUATE_FIELD_FAILED

        source = getattr(source, component, None)

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
    if provider_name == "SwiftInfo":
        provider = SwiftInfo

    if not provider:
        asserts.expect_failure(
            env,
            "Provider '{}' is not supported.".format(provider_name),
        )
        return None

    if provider in target:
        return target[provider]

    asserts.expect_failure(
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

def _prettify_list(items):
    """Returns the given list formatted as a multiline string.

    Args:
        items: A list.

    Returns:
        A multiline string containing the list items, one per line, that can be
        output as part of an assertion failure message.
    """
    return "[\n    " + ",\n    ".join(items) + "\n]"

def _normalize_collection(env, collection):
    """Returns the given collection as a list, regardless of its original type.

    If the type is not a collection or a supported type of collection, then an
    assertion failure is registered in the test environment.

    Args:
        env: The analysis test environment.
        collection: The collection to normalize. Supported types are lists and
            depsets.

    Returns:
        A list containing the same items in `collection`.
    """
    if types.is_depset(collection):
        return collection.to_list()
    elif types.is_list(collection):
        return collection
    else:
        asserts.expect_failure(
            env,
            "Expected a depset or list, but got '{}'.".format(type(collection)),
        )
        return None

def _compare_expected_files(env, access_description, expected, actual):
    """Implements the `expected_files` comparison.

    This compares a set of files retrieved from a provider field against a list
    of expected strings that are equal to or suffixes of the paths to those
    files.

    Args:
        env: The analysis test environment.
        access_description: A target/provider/field access description string
            printed in assertion failure messages.
        expected: The list of expected file path suffixes.
        actual: The collection of files obtained from the provider.
    """
    actual = _normalize_collection(env, actual)
    if actual == None:
        return

    if any([type(item) != "File" for item in actual]):
        asserts.expect_failure(
            env,
            "Expected '{}' to contain only files, but got {}.".format(
                _prettify_list(actual),
            ),
        )
        return

    remaining = list(actual)

    # For every expected file, pick off the first actual that we find that has
    # the expected string as a suffix.
    failed = False
    for suffix in expected:
        if not remaining:
            # It's a failure if we are still expecting files but there are no
            # more actual files.
            failed = True
            break

        for i in range(len(remaining)):
            actual_path = remaining[i].path
            if actual_path.endswith(suffix):
                remaining.pop(i)
                break

    # The remaining list should be empty at this point, if we found all of the
    # expected files.
    if remaining:
        failed = True

    asserts.false(
        env,
        failed,
        "Expected '{}' to be files ending in {}, but got {}.".format(
            access_description,
            _prettify_list(expected),
            _prettify_list([f.path for f in actual]),
        ),
    )

def _provider_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = ctx.attr.target_under_test

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

This list is evaluated as file path suffixes; files are matched if a string in
this list matches the end of a path in the actual list of files. This allows the
test to be unconcerned about specific configuration details, such as output
directories for generated files.
""",
            ),
            "field": attr.string(
                mandatory = True,
                doc = """\
The field name or dotted field path of the provider that should be tested.
""",
            ),
            "provider": attr.string(
                mandatory = True,
                doc = """\
The name of the provider expected to be propagated by the target under test, and
on which the field will be checked.

Currently, the only recognized provider is `SwiftInfo`.
""",
            ),
        },
    )

# A default instantiation of the rule when no custom config settings are needed.
provider_test = make_provider_test_rule()

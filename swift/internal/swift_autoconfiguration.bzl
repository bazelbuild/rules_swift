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

"""Definitions for autoconfiguring Swift toolchains.

At this time, only the Linux toolchain uses this capability. The Xcode toolchain
determines which
features are supported using Xcode version checks in xcode_toolchain.bzl.

NOTE: This file is loaded from repositories.bzl, before any workspace
dependencies have been downloaded. Therefore, only files within this repository
should be loaded here. Do not load anything else, even common libraries like
Skylib.
"""

load(
    "@build_bazel_rules_swift//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_ENABLE_SKIP_FUNCTION_BODIES",
    "SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS",
    "SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
)

def _scratch_file(repository_ctx, temp_dir, name, content = ""):
    """Creates and returns a scratch file with the given name and content.

    Args:
        repository_ctx: The repository context.
        temp_dir: The `path` to the temporary directory where the file should be
            created.
        name: The name of the scratch file.
        content: The text to write into the scratch file.

    Returns:
        The `path` to the file that was created.
    """
    path = temp_dir.get_child(name)
    repository_ctx.file(path, content)
    return path

def _swift_succeeds(repository_ctx, swiftc_path, *args):
    """Returns True if an invocation of the Swift compiler is successful.

    Args:
        repository_ctx: The repository context.
        swiftc_path: The `path` to the `swiftc` executable to spawn.
        *args: Zero or more arguments to pass to `swiftc` on the command line.

    Returns:
        True if the invocation was successful (a zero exit code); otherwise,
        False.
    """
    swift_result = repository_ctx.execute([swiftc_path] + list(args))
    return swift_result.return_code == 0

def _check_enable_batch_mode(repository_ctx, swiftc_path, _temp_dir):
    """Returns True if `swiftc` supports batch mode."""
    return _swift_succeeds(
        repository_ctx,
        swiftc_path,
        "-version",
        "-enable-batch-mode",
    )

def _check_skip_function_bodies(repository_ctx, swiftc_path, _temp_dir):
    """Returns True if `swiftc` supports skip function bodies."""
    return _swift_succeeds(
        repository_ctx,
        swiftc_path,
        "-version",
        "-experimental-skip-non-inlinable-function-bodies",
    )

def _check_debug_prefix_map(repository_ctx, swiftc_path, _temp_dir):
    """Returns True if `swiftc` supports debug prefix mapping."""
    return _swift_succeeds(
        repository_ctx,
        swiftc_path,
        "-version",
        "-debug-prefix-map",
        "foo=bar",
    )

def _check_supports_private_deps(repository_ctx, swiftc_path, temp_dir):
    """Returns True if `swiftc` supports implementation-only imports."""
    source_file = _scratch_file(
        repository_ctx,
        temp_dir,
        "main.swift",
        """\
@_implementationOnly import Foundation
print("Hello")
""",
    )
    return _swift_succeeds(
        repository_ctx,
        swiftc_path,
        source_file,
    )

def _check_use_response_files(repository_ctx, swiftc_path, temp_dir):
    """Returns True if `swiftc` supports the use of response files."""
    param_file = _scratch_file(
        repository_ctx,
        temp_dir,
        "check-response-files.params",
        "-version",
    )
    return _swift_succeeds(
        repository_ctx,
        swiftc_path,
        "@{}".format(param_file),
    )

def _write_swift_version(repository_ctx, swiftc_path):
    """Write a file containing the current Swift version info

    This is used to encode the current version of Swift as an input for caching

    Args:
        repository_ctx: The repository context.
        swiftc_path: The `path` to the `swiftc` executable.

    Returns:
        The written file containing the version info
    """
    result = repository_ctx.execute([swiftc_path, "-version"])
    contents = "unknown"
    if result.return_code == 0:
        contents = result.stdout.strip()

    filename = "swift_version"
    repository_ctx.file(filename, contents, executable = False)
    return filename

def _compute_feature_values(repository_ctx, swiftc_path):
    """Computes a list of supported/unsupported features by running checks.

    The result of this function is a list of feature names that can be provided
    as the `features` attribute of a toolchain rule. That is, enabled features
    are represented by the feature name itself, and unsupported features are
    represented as a hyphen ("-") followed by the feature name.

    Args:
        repository_ctx: The repository context.
        swiftc_path: The `path` to the `swiftc` executable.

    Returns:
        A list of feature strings that can be provided as the `features`
        attribute of a toolchain rule.
    """
    feature_values = []
    for feature, checker in _FEATURE_CHECKS.items():
        # Create a scratch directory in which the check function can write any
        # files that it needs to pass to `swiftc`.
        mktemp_result = repository_ctx.execute([
            "mktemp",
            "-d",
            "tmp.autoconfiguration.XXXXXXXXXX",
        ])
        temp_dir = repository_ctx.path(mktemp_result.stdout.strip())

        if checker(repository_ctx, swiftc_path, temp_dir):
            feature_values.append(feature)
        else:
            feature_values.append("-{}".format(feature))

        # Clean up the scratch directory.
        # TODO(allevato): Replace with `repository_ctx.delete` once it's
        # released.
        repository_ctx.execute(["rm", "-r", temp_dir])

    return feature_values

# Features whose support should be checked and the functions used to check them.
# A check function has the following signature:
#
#     def <function_name>(repository_ctx, swiftc_path, temp_dir)
#
# Where `swiftc_path` and `temp_dir` are `path` structures denoting the path to
# the `swiftc` executable and a scratch directory, respectively. The function
# should return True if the feature is supported.
_FEATURE_CHECKS = {
    SWIFT_FEATURE_DEBUG_PREFIX_MAP: _check_debug_prefix_map,
    SWIFT_FEATURE_ENABLE_BATCH_MODE: _check_enable_batch_mode,
    SWIFT_FEATURE_ENABLE_SKIP_FUNCTION_BODIES: _check_skip_function_bodies,
    SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS: _check_supports_private_deps,
    SWIFT_FEATURE_USE_RESPONSE_FILES: _check_use_response_files,
}

def _create_linux_toolchain(repository_ctx):
    """Creates BUILD targets for the Swift toolchain on Linux.

    Args:
      repository_ctx: The repository rule context.
    """
    cc = repository_ctx.os.environ.get("CC") or ""
    if "clang" not in cc:
        fail("ERROR: rules_swift uses Bazel's CROSSTOOL to link, but Swift " +
             "requires that the driver used is clang. Please set `CC=clang` " +
             "in your environment before invoking Bazel.")

    path_to_swiftc = repository_ctx.which("swiftc")
    if not path_to_swiftc:
        fail("No 'swiftc' executable found in $PATH")

    root = path_to_swiftc.dirname.dirname
    feature_values = _compute_feature_values(repository_ctx, path_to_swiftc)
    version_file = _write_swift_version(repository_ctx, path_to_swiftc)

    # TODO: This should be removed so that private headers can be used with
    # explicit modules, but the build targets for CgRPC need to be cleaned up
    # first because they contain C++ code.
    feature_values.append(SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS)

    repository_ctx.file(
        "BUILD",
        """
load(
    "@build_bazel_rules_swift//swift/internal:swift_toolchain.bzl",
    "swift_toolchain",
)

package(default_visibility = ["//visibility:public"])

swift_toolchain(
    name = "toolchain",
    arch = "x86_64",
    features = [{feature_list}],
    os = "linux",
    root = "{root}",
    version_file = "{version_file}",
)
""".format(
            feature_list = ", ".join([
                '"{}"'.format(feature)
                for feature in feature_values
            ]),
            root = root,
            version_file = version_file,
        ),
    )

def _create_xcode_toolchain(repository_ctx):
    """Creates BUILD targets for the Swift toolchain on macOS using Xcode.

    Args:
      repository_ctx: The repository rule context.
    """
    feature_values = [
        # TODO: This should be removed so that private headers can be used with
        # explicit modules, but the build targets for CgRPC need to be cleaned
        # up first because they contain C++ code.
        SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS,
    ]

    repository_ctx.file(
        "BUILD",
        """
load(
    "@build_bazel_rules_swift//swift/internal:xcode_swift_toolchain.bzl",
    "xcode_swift_toolchain",
)

package(default_visibility = ["//visibility:public"])

xcode_swift_toolchain(
    name = "toolchain",
    features = [{feature_list}],
)
""".format(
            feature_list = ", ".join([
                '"{}"'.format(feature)
                for feature in feature_values
            ]),
        ),
    )

def _swift_autoconfiguration_impl(repository_ctx):
    # TODO(allevato): This is expedient and fragile. Use the
    # platforms/toolchains APIs instead to define proper toolchains, and make it
    # possible to support non-Xcode toolchains on macOS as well.
    os_name = repository_ctx.os.name.lower()
    if os_name.startswith("mac os"):
        _create_xcode_toolchain(repository_ctx)
    else:
        _create_linux_toolchain(repository_ctx)

swift_autoconfiguration = repository_rule(
    environ = ["CC", "PATH"],
    implementation = _swift_autoconfiguration_impl,
)

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

"""Common attributes used by multiple Swift build rules."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo")
load(":providers.bzl", "SwiftCompilerPluginInfo")

visibility([
    "@build_bazel_rules_swift//swift/...",
])

C_HEADER_EXTENSIONS = ["h", "hh", "hpp", "hxx", "inc"]
C_SOURCE_EXTENSIONS = ["c", "cc", "cpp", "cxx", "m", "mm"]

def swift_common_rule_attrs(
        additional_deps_aspects = [],
        additional_deps_providers = []):
    return {
        "data": attr.label_list(
            allow_files = True,
            doc = """\
The list of files needed by this target at runtime.

Files and targets named in the `data` attribute will appear in the `*.runfiles`
area of this target, if it has one. This may include data files needed by a
binary or library, or other programs needed by it.
""",
        ),
        "deps": swift_deps_attr(
            additional_deps_providers = additional_deps_providers,
            aspects = additional_deps_aspects,
            doc = """\
A list of targets that are dependencies of the target being built, which will be
linked into that target.

If the Swift toolchain supports implementation-only imports (`private_deps` on
`swift_library`), then targets in `deps` are treated as regular
(non-implementation-only) imports that are propagated both to their direct and
indirect (transitive) dependents.
""",
        ),
        # Deprecated, but Starlark rules do not inherit `licenses` by default
        # (see b/169635467).
        # buildifier: disable=attr-license
        # buildifier: disable=attr-licenses
        "licenses": attr.license(),
    }

def swift_compilation_attrs(
        additional_deps_aspects = [],
        additional_deps_providers = [],
        requires_srcs = True):
    """Returns an attribute dictionary for rules that compile Swift code.

    The returned dictionary contains the subset of attributes that are shared by
    the `swift_binary`, `swift_library`, and `swift_test` rules that deal with
    inputs and options for compilation. Users who are authoring custom rules
    that compile Swift code but not as a library can add this dictionary to
    their own rule's attributes to give it a familiar API.

    Do note, however, that it is the responsibility of the rule implementation
    to retrieve the values of those attributes and pass them correctly to the
    other `swift_common` APIs.

    There is a hierarchy to the attribute sets offered by the `swift_common`
    API:

    1.  If you only need access to the toolchain for its tools and libraries but
        are not doing any compilation, use `toolchain_attrs`.
    2.  If you need to invoke compilation actions but are not making the
        resulting object files into a static or shared library, use
        `compilation_attrs`.
    3.  If you want to provide a rule interface that is suitable as a drop-in
        replacement for `swift_library`, use `library_rule_attrs`.

    Each of the attribute functions in the list above also contains the
    attributes from the earlier items in the list.

    Args:
        additional_deps_aspects: A list of additional aspects that should be
            applied to `deps`. Defaults to the empty list. These must be passed
            by the individual rules to avoid potential circular dependencies
            between the API and the aspects; the API loaded the aspects
            directly, then those aspects would not be able to load the API.
        additional_deps_providers: A list of lists representing additional
            providers that should be allowed by the `deps` attribute of the
            rule.
        requires_srcs: Indicates whether the `srcs` attribute should be marked
            as mandatory and non-empty. Defaults to `True`.

    Returns:
        A new attribute dictionary that can be added to the attributes of a
        custom build rule to provide a similar interface to `swift_binary`,
        `swift_library`, and `swift_test`.
    """
    return dicts.add(
        swift_common_rule_attrs(
            additional_deps_aspects = additional_deps_aspects,
            additional_deps_providers = additional_deps_providers,
        ),
        {
            "srcs": attr.label_list(
                allow_empty = not requires_srcs,
                allow_files = (
                    ["swift"] + C_HEADER_EXTENSIONS + C_SOURCE_EXTENSIONS
                ),
                doc = """\
A list of source files that will be compiled into the library. These can be
`.swift` files, or in the case of mixed-language modules, C/Objective-C source
files may also be included. C/Objective-C source files must be ARC-compatible
and will be compiled using the C toolchain resolved by Bazel for the desired
configuration. C/Objective-C header files listed in `srcs` will be treated as
_private headers_ of the module (that is, not propagated to dependent targets)
and must be parsable as C/Objective-C like any other header imported by Swift.

Except in very rare circumstances, a Swift source file should only appear in a
single `swift_*` target. Adding the same source file to multiple `swift_*`
targets can lead to binary bloat and/or symbol collisions. If specific sources
need to be shared by multiple targets, consider factoring them out into their
own `swift_library` instead.
""",
                flags = ["DIRECT_COMPILE_TIME_INPUT"],
                mandatory = requires_srcs,
            ),
            "copts": attr.string_list(
                doc = """\
Additional compiler options that should be passed to `swiftc`. These strings are
subject to `$(location ...)` expansion.
""",
            ),
            "c_copts": attr.string_list(
                doc = """\
Additional compiler options that should be passed to the C compiler when
compiling any C/Objective-C sources that are part of a mixed language module.
These strings are subject to `$(location ...)` expansion.
""",
            ),
            "defines": attr.string_list(
                doc = """\
A list of defines to add to the compilation command line.

Note that unlike C-family languages, Swift defines do not have values; they are
simply identifiers that are either defined or undefined. So strings in this list
should be simple identifiers, **not** `name=value` pairs.

Each string is prepended with `-D` and added to the command line. Unlike
`copts`, these flags are added for the target and every target that depends on
it, so use this attribute with caution. It is preferred that you add defines
directly to `copts`, only using this feature in the rare case that a library
needs to propagate a symbol up to those that depend on it.
""",
            ),
            "module_name": attr.string(
                doc = """\
The name of the Swift module being built.

If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading `//` and replacing `/`, `:`, and other
non-identifier characters with underscores.
""",
            ),
            "plugins": attr.label_list(
                cfg = "exec",
                doc = """\
A list of `swift_compiler_plugin` targets that should be loaded by the compiler
when compiling this module and any modules that directly depend on it.
""",
                providers = [[SwiftCompilerPluginInfo]],
            ),
            "swiftc_inputs": attr.label_list(
                allow_files = True,
                doc = """\
Additional files that are referenced using `$(location ...)` in attributes that
support location expansion.
""",
            ),
        },
    )

def swift_config_attrs():
    """Returns the Starlark configuration flags and settings attributes.

    Returns:
        A dictionary of configuration attributes to be added to rules that read
        configuration settings.
    """
    return {
        "_per_module_swiftcopt": attr.label(
            default = "@build_bazel_rules_swift//swift:per_module_swiftcopt",
        ),
    }

def swift_deps_attr(*, additional_deps_providers = [], doc, **kwargs):
    """Returns an attribute suitable for representing Swift rule dependencies.

    The returned attribute will be configured to accept targets that propagate
    `CcInfo` or `SwiftInfo` providers.

    Args:
        additional_deps_providers: A list of lists representing additional
            providers that should be allowed by the `deps` attribute of the
            rule.
        doc: A string containing a summary description of the purpose of the
            attribute. This string will be followed by additional text that
            lists the permitted kinds of targets that may go in this attribute.
        **kwargs: Additional arguments that are passed to `attr.label_list`
            unmodified.

    Returns:
        A rule attribute.
    """
    return attr.label_list(
        doc = doc + """\

Allowed kinds of dependencies are:

*   `swift_library` (or anything propagating `SwiftInfo`)

*   `cc_library` and `objc_library` (or anything propagating `CcInfo`)
""",
        providers = [[CcInfo], [SwiftInfo]] + additional_deps_providers,
        **kwargs
    )

def swift_library_rule_attrs(
        additional_deps_aspects = [],
        requires_srcs = True):
    """Returns an attribute dictionary for `swift_library`-like rules.

    The returned dictionary contains the same attributes that are defined by the
    `swift_library` rule (including the private `_toolchain` attribute that
    specifies the toolchain dependency). Users who are authoring custom rules
    can use this dictionary verbatim or add other custom attributes to it in
    order to make their rule a drop-in replacement for `swift_library` (for
    example, if writing a custom rule that does some preprocessing or generation
    of sources and then compiles them).

    Do note, however, that it is the responsibility of the rule implementation
    to retrieve the values of those attributes and pass them correctly to the
    other `swift_common` APIs.

    There is a hierarchy to the attribute sets offered by the `swift_common`
    API:

    1.  If you only need access to the toolchain for its tools and libraries but
        are not doing any compilation, use `toolchain_attrs`.
    2.  If you need to invoke compilation actions but are not making the
        resulting object files into a static or shared library, use
        `compilation_attrs`.
    3.  If you want to provide a rule interface that is suitable as a drop-in
        replacement for `swift_library`, use `library_rule_attrs`.

    Each of the attribute functions in the list above also contains the
    attributes from the earlier items in the list.

    Args:
        additional_deps_aspects: A list of additional aspects that should be
            applied to `deps`. Defaults to the empty list. These must be passed
            by the individual rules to avoid potential circular dependencies
            between the API and the aspects; the API loaded the aspects
            directly, then those aspects would not be able to load the API.
        requires_srcs: Indicates whether the `srcs` attribute should be marked
            as mandatory and non-empty. Defaults to `True`.

    Returns:
        A new attribute dictionary that can be added to the attributes of a
        custom build rule to provide the same interface as `swift_library`.
    """
    return dicts.add(
        swift_compilation_attrs(
            additional_deps_aspects = additional_deps_aspects,
            requires_srcs = requires_srcs,
        ),
        swift_config_attrs(),
        {
            "library_evolution": attr.bool(
                default = False,
                doc = """\
Indicates whether the Swift code should be compiled with library evolution mode
enabled.

This attribute should be used to compile a module that will be distributed as
part of a client-facing (non-implementation-only) module in a library or
framework that will be distributed for use outside of the Bazel build graph.
Setting this to true will compile the module with the `-library-evolution` flag
and emit a `.swiftinterface` file as one of the compilation outputs.
""",
                mandatory = False,
            ),
            "linkopts": attr.string_list(
                doc = """\
Additional linker options that should be passed to the linker for the binary
that depends on this target. These strings are subject to `$(location ...)`
expansion.
""",
            ),
            "alwayslink": attr.bool(
                default = True,
                doc = """\
If `False`, any binary that depends (directly or indirectly) on this Swift module
will only link in all the object files for the files listed in `srcs` when there
is a direct symbol reference.

Swift protocol conformances don't create linker references. Likewise, if the
Swift code has Objective-C classes/methods, their usage does not always result in
linker references.

_"All the object files"_ for this module is also somewhat fuzzy. Unlike C, C++,
and Objective-C, where each source file results in a `.o` file; for Swift the
number of .o files depends on the compiler options
(`-wmo`/`-whole-module-optimization`, `-num-threads`). That makes relying on
linker reference more fragile, and any individual .swift file in `srcs` may/may
not get picked up based on the linker references to other files that happen to
get batched into a single `.o` by the compiler options used.

Swift Package Manager always passes the individual `.o` files to the linker
instead of using intermediate static libraries, so it effectively is the same
as `alwayslink = True`.
""",
            ),
            "generated_header_name": attr.string(
                doc = """\
The name of the generated Objective-C interface header. This name must end with
a `.h` extension and cannot contain any path separators.

If this attribute is not specified, then the default behavior is to name the
header `${target_name}-Swift.h`.

It is an error to specify a value for this attribute when `generates_header` is
False.
""",
                mandatory = False,
            ),
            "generates_header": attr.bool(
                default = False,
                doc = """\
If True, an Objective-C header will be generated for this target, in the same
build package where the target is defined. By default, the name of the header is
`${target_name}-Swift.h`; this can be changed using the `generated_header_name`
attribute.

Targets should only set this attribute to True if they export Objective-C APIs.
A header generated for a target that does not export Objective-C APIs will be
effectively empty (except for a large amount of prologue and epilogue code) and
this is generally wasteful because the extra file needs to be propagated in the
build graph and, when explicit modules are enabled, extra actions must be
executed to compile the Objective-C module for the generated header.

#### Mixed language modules

When writing a mixed language module (e.g., a `swift_library` containing both
Swift sources and C/Objective-C sources), it is permitted for _sources_ to
import this header to access APIs exported from Swift, but it is _not permitted_
for other _headers_ to import the generated header. This would result in a
circular dependency between the modules. If a header needs to refer to a symbol
exported from Swift, then it must forward-declare it (forward declarations to
symbols in the same module are not problematic, unlike forward declarations to
symbols in other modules).
""",
                mandatory = False,
            ),
        },
    )

def swift_toolchain_driver_attrs():
    """Returns attributes used to attach custom drivers to toolchains.

    These attributes are useful for compiler development alongside Bazel. The
    public attribute (`swift_executable`) lets a custom driver be permanently
    associated with a particular toolchain instance. If not specified, the
    private default is associated with a command-line option that can be used to
    provide a custom driver at build time.

    Returns:
        A dictionary of attributes that should be added to a toolchain rule.
    """
    return {
        "swift_executable": attr.label(
            allow_single_file = True,
            cfg = "exec",
            doc = """\
A replacement Swift driver executable.

If this is empty, the default Swift driver in the toolchain will be used.
Otherwise, this binary will be used and `--driver-mode` will be passed to ensure
that it is invoked in the correct mode (i.e., `swift`, `swiftc`, etc.).
""",
        ),
        "_default_swift_executable": attr.label(
            allow_files = True,
            cfg = "exec",
            default = Label(
                "@build_bazel_rules_swift//swift:default_swift_executable",
            ),
        ),
    }

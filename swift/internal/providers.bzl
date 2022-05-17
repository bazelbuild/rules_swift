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

"""Internal providers and utility functions.
Note that some of these definitions are exported via the `swift_common` module.
*Public* providers should be defined in `swift:providers.bzl`, not in this file
(`swift/internal:providers.bzl`).
"""

load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo")

def create_module(
        *,
        name,
        clang = None,
        const_gather_protocols = [],
        compilation_context = None,
        is_system = False,
        swift = None):
    """Creates a value containing Clang/Swift module artifacts of a dependency.

    It is possible for both `clang` and `swift` to be present; this is the case
    for Swift modules that generate an Objective-C header, where the Swift
    module artifacts are propagated in the `swift` context and the generated
    header and module map are propagated in the `clang` context.

    Though rare, it is also permitted for both the `clang` and `swift` arguments
    to be `None`. One example of how this can be used is to model system
    dependencies (like Apple SDK frameworks) that are implicitly available as
    part of a non-hermetic SDK (Xcode) but do not propagate any artifacts of
    their own. This would only apply in a build using implicit modules, however;
    when using explicit modules, one would propagate the module artifacts
    explicitly. But allowing for the empty case keeps the build graph consistent
    if switching between the two modes is necessary, since it will not change
    the set of transitive module names that are propagated by dependencies
    (which other build rules may want to depend on for their own analysis).

    Args:
        name: The name of the module.
        clang: A value returned by `swift_common.create_clang_module` that
            contains artifacts related to Clang modules, such as a module map or
            precompiled module. This may be `None` if the module is a pure Swift
            module with no generated Objective-C interface.
        const_gather_protocols: A list of protocol names from which constant
            values should be extracted from source code that takes this module
            as a *direct* dependency.
        compilation_context: A value returned from
            `swift_common.create_compilation_context` that contains the
            context needed to compile the module being built. This may be `None`
            if the module wasn't compiled from sources.
        is_system: Indicates whether the module is a system module. The default
            value is `False`. System modules differ slightly from non-system
            modules in the way that they are passed to the compiler. For
            example, non-system modules have their Clang module maps passed to
            the compiler in both implicit and explicit module builds. System
            modules, on the other hand, do not have their module maps passed to
            the compiler in implicit module builds because there is currently no
            way to indicate that modules declared in a file passed via
            `-fmodule-map-file` should be treated as system modules even if they
            aren't declared with the `[system]` attribute, and some system
            modules may not build cleanly with respect to warnings otherwise.
            Therefore, it is assumed that any module with `is_system == True`
            must be able to be found using import search paths in order for
            implicit module builds to succeed.
        swift: A value returned by `swift_common.create_swift_module` that
            contains artifacts related to Swift modules, such as the
            `.swiftmodule`, `.swiftdoc`, and/or `.swiftinterface` files emitted
            by the compiler. This may be `None` if the module is a pure
            C/Objective-C module.

    Returns:
        A `struct` containing the `name`, `clang`, `is_system`, and `swift`
        fields provided as arguments.
    """
    return struct(
        clang = clang,
        const_gather_protocols = tuple(const_gather_protocols),
        compilation_context = compilation_context,
        is_system = is_system,
        name = name,
        swift = swift,
    )

def create_clang_module(
        *,
        compilation_context,
        module_map,
        precompiled_module = None,
        strict_includes = None):
    """Creates a value representing a Clang module used as a Swift dependency.

    Args:
        compilation_context: A `CcCompilationContext` that contains the header
            files and other context (such as include paths, preprocessor
            defines, and so forth) needed to compile this module as an explicit
            module.
        module_map: The text module map file that defines this module. This
            argument may be specified as a `File` or as a `string`; in the
            latter case, it is assumed to be the path to a file that cannot
            be provided as an action input because it is outside the workspace
            (for example, the module map for a module from an Xcode SDK).
        precompiled_module: A `File` representing the precompiled module (`.pcm`
            file) if one was emitted for the module. This may be `None` if no
            explicit module was built for the module; in that case, targets that
            depend on the module will fall back to the text module map and
            headers.
        strict_includes: A `depset` of strings representing additional Clang
            include paths that should be passed to the compiler when this module
            is a _direct_ dependency of the module being compiled. May be
            `None`. **This field only exists to support a specific legacy use
            case and should otherwise not be used, as it is fundamentally
            incompatible with Swift's import model.**

    Returns:
        A `struct` containing the `compilation_context`, `module_map`,
        `precompiled_module`, and `strict_includes` fields provided as
        arguments.
    """
    return struct(
        compilation_context = compilation_context,
        module_map = module_map,
        precompiled_module = precompiled_module,
        strict_includes = strict_includes,
    )

def create_swift_module(
        *,
        swiftdoc,
        swiftmodule,
        ast_files = [],
        defines = [],
        indexstore = None,
        plugins = [],
        swiftsourceinfo = None,
        swiftinterface = None,
        private_swiftinterface = None,
        const_protocols_to_gather = []):
    """Creates a value representing a Swift module use as a Swift dependency.

    Args:
        swiftdoc: The `.swiftdoc` file emitted by the compiler for this module.
        swiftmodule: The `.swiftmodule` file emitted by the compiler for this
            module.
        ast_files: A list of `File`s output from the `DUMP_AST` action.
        defines: A list of defines that will be provided as `copts` to targets
            that depend on this module. If omitted, the empty list will be used.
        indexstore: A `File` representing the directory that contains the index
            store data generated by the compiler if the
            `"swift.index_while_building"` feature is enabled, otherwise this
            will be `None`.
        plugins: A list of `SwiftCompilerPluginInfo` providers representing
            compiler plugins that are required by this module and should be
            loaded by the compiler when this module is directly depended on.
        private_swiftinterface: The `.private.swiftinterface` file emitted by
            the compiler for this module. May be `None` if no private module
            interface file was emitted.
        swiftsourceinfo: The `.swiftsourceinfo` file emitted by the compiler for
            this module. May be `None` if no source info file was emitted.
        swiftinterface: The `.swiftinterface` file emitted by the compiler for
            this module. May be `None` if no module interface file was emitted.
        const_protocols_to_gather: A list of protocol names from which constant
            values should be extracted from source code that takes this module
            as a *direct* dependency.

    Returns:
        A `struct` containing the `ast_files`, `defines`, `indexstore,
        `swiftdoc`, `swiftmodule`, and `swiftinterface` fields
        provided as arguments.
    """
    return struct(
        ast_files = tuple(ast_files),
        defines = tuple(defines),
        plugins = plugins,
        private_swiftinterface = private_swiftinterface,
        indexstore = indexstore,
        swiftdoc = swiftdoc,
        swiftinterface = swiftinterface,
        swiftmodule = swiftmodule,
        swiftsourceinfo = swiftsourceinfo,
        const_protocols_to_gather = tuple(const_protocols_to_gather),
    )

def create_swift_info(
        *,
        direct_swift_infos = [],
        modules = [],
        swift_infos = []):
    """Creates a new `SwiftInfo` provider with the given values.

    This function is recommended instead of directly creating a `SwiftInfo`
    provider because it encodes reasonable defaults for fields that some rules
    may not be interested in and ensures that the direct and transitive fields
    are set consistently.

    This function can also be used to do a simple merge of `SwiftInfo`
    providers, by leaving the `modules` argument unspecified. In that case, the
    returned provider will not represent a true Swift module; it is merely a
    "collector" for other dependencies.

    Args:
        direct_swift_infos: A list of `SwiftInfo` providers from dependencies
            whose direct modules should be treated as direct modules in the
            resulting provider, in addition to their transitive modules being
            merged.
        modules: A list of values (as returned by `swift_common.create_module`)
            that represent Clang and/or Swift module artifacts that are direct
            outputs of the target being built.
        swift_infos: A list of `SwiftInfo` providers from dependencies whose
            transitive modules should be merged into the resulting provider.

    Returns:
        A new `SwiftInfo` provider with the given values.
    """

    direct_modules = modules + [
        module
        for provider in direct_swift_infos
        for module in provider.direct_modules
    ]
    transitive_modules = [
        provider.transitive_modules
        for provider in direct_swift_infos + swift_infos
    ]

    return SwiftInfo(
        direct_modules = direct_modules,
        transitive_modules = depset(
            direct_modules,
            transitive = transitive_modules,
        ),
    )

# Note that this provider appears here and not in `providers.bzl` because it is
# not public API. It is meant to be a "write-only" provider; one that targets
# can propagate but should not attempt to read.
SwiftInteropInfo = provider(
    doc = """\
Contains minimal information required to allow `swift_clang_module_aspect` to
manage the creation of a `SwiftInfo` provider for a C/Objective-C target.
""",
    fields = {
        "exclude_headers": """\
A `list` of `File`s representing headers that should be excluded from the
module, if a module map is being automatically generated based on the headers in
the target's compilation context.
""",
        "module_map": """\
A `File` representing an existing module map that should be used to represent
the module, or `None` if the module map should be generated based on the headers
in the target's compilation context.
""",
        "module_name": """\
A string denoting the name of the module, or `None` if the name should be
derived automatically from the target label.
""",
        "requested_features": """\
A list of features that should be enabled for the target, in addition to those
supplied in the `features` attribute, unless the feature is otherwise marked as
unsupported (either on the target or by the toolchain). This allows the rule
implementation to supply an additional set of fixed features that should always
be enabled when the aspect processes that target; for example, a rule can
request that `swift.emit_c_module` always be enabled for its targets even if it
is not explicitly enabled in the toolchain or on the target directly.
""",
        "suppressed": """\
A `bool` indicating whether the module that the aspect would create for the
target should instead be suppressed.
""",
        "swift_infos": """\
A list of `SwiftInfo` providers from dependencies of the target, which will be
merged with the new `SwiftInfo` created by the aspect.
""",
        "unsupported_features": """\
A list of features that should be disabled for the target, in addition to those
supplied as negations in the `features` attribute. This allows the rule
implementation to supply an additional set of fixed features that should always
be disabled when the aspect processes that target; for example, a rule that
processes frameworks with headers that do not follow strict layering can request
that `swift.strict_module` always be disabled for its targets even if it is
enabled by default in the toolchain.
""",
    },
)

def create_swift_interop_info(
        *,
        exclude_headers = [],
        module_map = None,
        module_name = None,
        requested_features = [],
        suppressed = False,
        swift_infos = [],
        unsupported_features = []):
    """Returns a provider that lets a target expose C/Objective-C APIs to Swift.

    The provider returned by this function allows custom build rules written in
    Starlark to be uninvolved with much of the low-level machinery involved in
    making a Swift-compatible module. Such a target should propagate a `CcInfo`
    provider whose compilation context contains the headers that it wants to
    make into a module, and then also propagate the provider returned from this
    function.

    The simplest usage is for a custom rule to call
    `swift_common.create_swift_interop_info` passing it only the list of
    `SwiftInfo` providers from its dependencies; this tells
    `swift_clang_module_aspect` to derive the module name from the target label
    and create a module map using the headers from the compilation context.

    If the custom rule has reason to provide its own module name or module map,
    then it can do so using the `module_name` and `module_map` arguments.

    When a rule returns this provider, it must provide the full set of
    `SwiftInfo` providers from dependencies that will be merged with the one
    that `swift_clang_module_aspect` creates for the target itself; the aspect
    will not do so automatically. This allows the rule to not only add extra
    dependencies (such as support libraries from implicit attributes) but also
    exclude dependencies if necessary.

    Args:
        exclude_headers: A `list` of `File`s representing headers that should be
            excluded from the module if the module map is generated.
        module_map: A `File` representing an existing module map that should be
            used to represent the module, or `None` (the default) if the module
            map should be generated based on the headers in the target's
            compilation context. If this argument is provided, then
            `module_name` must also be provided.
        module_name: A string denoting the name of the module, or `None` (the
            default) if the name should be derived automatically from the target
            label.
        requested_features: A list of features (empty by default) that should be
            requested for the target, which are added to those supplied in the
            `features` attribute of the target. These features will be enabled
            unless they are otherwise marked as unsupported (either on the
            target or by the toolchain). This allows the rule implementation to
            have additional control over features that should be supported by
            default for all instances of that rule as if it were creating the
            feature configuration itself; for example, a rule can request that
            `swift.emit_c_module` always be enabled for its targets even if it
            is not explicitly enabled in the toolchain or on the target
            directly.
        suppressed: A `bool` indicating whether the module that the aspect would
            create for the target should instead be suppressed.
        swift_infos: A list of `SwiftInfo` providers from dependencies, which
            will be merged with the new `SwiftInfo` created by the aspect.
        unsupported_features: A list of features (empty by default) that should
            be considered unsupported for the target, which are added to those
            supplied as negations in the `features` attribute. This allows the
            rule implementation to have additional control over features that
            should be disabled by default for all instances of that rule as if
            it were creating the feature configuration itself; for example, a
            rule that processes frameworks with headers that do not follow
            strict layering can request that `swift.strict_module` always be
            disabled for its targets even if it is enabled by default in the
            toolchain.

    Returns:
        A provider whose type/layout is an implementation detail and should not
        be relied upon.
    """
    if module_map:
        if not module_name:
            fail("'module_name' must be specified when 'module_map' is " +
                 "specified.")
        if exclude_headers:
            fail("'exclude_headers' may not be specified when 'module_map' " +
                 "is specified.")

    return SwiftInteropInfo(
        exclude_headers = exclude_headers,
        module_map = module_map,
        module_name = module_name,
        requested_features = requested_features,
        suppressed = suppressed,
        swift_infos = swift_infos,
        unsupported_features = unsupported_features,
    )

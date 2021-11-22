<!-- Generated with Stardoc, Do Not Edit! -->
# Build API

The `swift_common` module provides API access to the behavior implemented
by the Swift build rules, so that other custom rules can invoke Swift
compilation and/or linking as part of their implementation.
<a id="#swift_common.cc_feature_configuration"></a>

## swift_common.cc_feature_configuration

<pre>
swift_common.cc_feature_configuration(<a href="#swift_common.cc_feature_configuration-feature_configuration">feature_configuration</a>)
</pre>

Returns the C++ feature configuration in a Swift feature configuration.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.cc_feature_configuration-feature_configuration"></a>feature_configuration |  The Swift feature configuration, as returned from <code>swift_common.configure_features</code>.   |  none |

**RETURNS**

A C++ `FeatureConfiguration` value (see
  [`cc_common.configure_features`](https://docs.bazel.build/versions/master/skylark/lib/cc_common.html#configure_features)
  for more information).


<a id="#swift_common.compilation_attrs"></a>

## swift_common.compilation_attrs

<pre>
swift_common.compilation_attrs(<a href="#swift_common.compilation_attrs-additional_deps_aspects">additional_deps_aspects</a>, <a href="#swift_common.compilation_attrs-requires_srcs">requires_srcs</a>)
</pre>

Returns an attribute dictionary for rules that compile Swift code.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.compilation_attrs-additional_deps_aspects"></a>additional_deps_aspects |  A list of additional aspects that should be applied to <code>deps</code>. Defaults to the empty list. These must be passed by the individual rules to avoid potential circular dependencies between the API and the aspects; the API loaded the aspects directly, then those aspects would not be able to load the API.   |  <code>[]</code> |
| <a id="swift_common.compilation_attrs-requires_srcs"></a>requires_srcs |  Indicates whether the <code>srcs</code> attribute should be marked as mandatory and non-empty. Defaults to <code>True</code>.   |  <code>True</code> |

**RETURNS**

A new attribute dictionary that can be added to the attributes of a
  custom build rule to provide a similar interface to `swift_binary`,
  `swift_library`, and `swift_test`.


<a id="#swift_common.compile"></a>

## swift_common.compile

<pre>
swift_common.compile(<a href="#swift_common.compile-actions">actions</a>, <a href="#swift_common.compile-additional_inputs">additional_inputs</a>, <a href="#swift_common.compile-copts">copts</a>, <a href="#swift_common.compile-defines">defines</a>, <a href="#swift_common.compile-deps">deps</a>, <a href="#swift_common.compile-feature_configuration">feature_configuration</a>,
                     <a href="#swift_common.compile-generated_header_name">generated_header_name</a>, <a href="#swift_common.compile-module_name">module_name</a>, <a href="#swift_common.compile-private_deps">private_deps</a>, <a href="#swift_common.compile-srcs">srcs</a>, <a href="#swift_common.compile-swift_toolchain">swift_toolchain</a>,
                     <a href="#swift_common.compile-target_name">target_name</a>, <a href="#swift_common.compile-workspace_name">workspace_name</a>)
</pre>

Compiles a Swift module.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.compile-actions"></a>actions |  The context's <code>actions</code> object.   |  none |
| <a id="swift_common.compile-additional_inputs"></a>additional_inputs |  A list of <code>File</code>s representing additional input files that need to be passed to the Swift compile action because they are referenced by compiler flags.   |  <code>[]</code> |
| <a id="swift_common.compile-copts"></a>copts |  A list of compiler flags that apply to the target being built. These flags, along with those from Bazel's Swift configuration fragment (i.e., <code>--swiftcopt</code> command line flags) are scanned to determine whether whole module optimization is being requested, which affects the nature of the output files.   |  <code>[]</code> |
| <a id="swift_common.compile-defines"></a>defines |  Symbols that should be defined by passing <code>-D</code> to the compiler.   |  <code>[]</code> |
| <a id="swift_common.compile-deps"></a>deps |  Non-private dependencies of the target being compiled. These targets are used as dependencies of both the Swift module being compiled and the Clang module for the generated header. These targets must propagate one of the following providers: <code>CcInfo</code>, <code>SwiftInfo</code>, or <code>apple_common.Objc</code>.   |  <code>[]</code> |
| <a id="swift_common.compile-feature_configuration"></a>feature_configuration |  A feature configuration obtained from <code>swift_common.configure_features</code>.   |  none |
| <a id="swift_common.compile-generated_header_name"></a>generated_header_name |  The name of the Objective-C generated header that should be generated for this module. If omitted, no header will be generated.   |  <code>None</code> |
| <a id="swift_common.compile-module_name"></a>module_name |  The name of the Swift module being compiled. This must be present and valid; use <code>swift_common.derive_module_name</code> to generate a default from the target's label if needed.   |  none |
| <a id="swift_common.compile-private_deps"></a>private_deps |  Private (implementation-only) dependencies of the target being compiled. These are only used as dependencies of the Swift module, not of the Clang module for the generated header. These targets must propagate one of the following providers: <code>CcInfo</code>, <code>SwiftInfo</code>, or <code>apple_common.Objc</code>.   |  <code>[]</code> |
| <a id="swift_common.compile-srcs"></a>srcs |  The Swift source files to compile.   |  none |
| <a id="swift_common.compile-swift_toolchain"></a>swift_toolchain |  The <code>SwiftToolchainInfo</code> provider of the toolchain.   |  none |
| <a id="swift_common.compile-target_name"></a>target_name |  The name of the target for which the code is being compiled, which is used to determine unique file paths for the outputs.   |  none |
| <a id="swift_common.compile-workspace_name"></a>workspace_name |  The name of the workspace for which the code is being compiled, which is used to determine unique file paths for some outputs.   |  none |

**RETURNS**

A tuple containing three elements:

  1.  A Swift module context (as returned by `swift_common.create_module`)
      that contains the Swift (and potentially C/Objective-C) compilation
      prerequisites of the compiled module. This should typically be
      propagated by a `SwiftInfo` provider of the calling rule.
  2.  A `CcCompilationOutputs` object (as returned by
      `cc_common.create_compilation_outputs`) that contains the compiled
      object files.
  3.  A struct containing:
      *   `ast_files`: A list of `File`s output from the `DUMP_AST`
          action.
      *   `indexstore`: A `File` representing the directory that contains
          the index store data generated by the compiler if
          index-while-building is enabled. May be None if no indexing was
          requested.


<a id="#swift_common.configure_features"></a>

## swift_common.configure_features

<pre>
swift_common.configure_features(<a href="#swift_common.configure_features-ctx">ctx</a>, <a href="#swift_common.configure_features-swift_toolchain">swift_toolchain</a>, <a href="#swift_common.configure_features-requested_features">requested_features</a>, <a href="#swift_common.configure_features-unsupported_features">unsupported_features</a>)
</pre>

Creates a feature configuration to be passed to Swift build APIs.

This function calls through to `cc_common.configure_features` to configure
underlying C++ features as well, and nests the C++ feature configuration
inside the Swift one. Users who need to call C++ APIs that require a feature
configuration can extract it by calling
`swift_common.cc_feature_configuration(feature_configuration)`.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.configure_features-ctx"></a>ctx |  The rule context.   |  none |
| <a id="swift_common.configure_features-swift_toolchain"></a>swift_toolchain |  The <code>SwiftToolchainInfo</code> provider of the toolchain being used to build. This is used to determine features that are enabled by default or unsupported by the toolchain, and the C++ toolchain associated with the Swift toolchain is used to create the underlying C++ feature configuration.   |  none |
| <a id="swift_common.configure_features-requested_features"></a>requested_features |  The list of features to be enabled. This is typically obtained using the <code>ctx.features</code> field in a rule implementation function.   |  <code>[]</code> |
| <a id="swift_common.configure_features-unsupported_features"></a>unsupported_features |  The list of features that are unsupported by the current rule. This is typically obtained using the <code>ctx.disabled_features</code> field in a rule implementation function.   |  <code>[]</code> |

**RETURNS**

An opaque value representing the feature configuration that can be
  passed to other `swift_common` functions. Note that the structure of
  this value should otherwise not be relied on or inspected directly.


<a id="#swift_common.create_clang_module"></a>

## swift_common.create_clang_module

<pre>
swift_common.create_clang_module(<a href="#swift_common.create_clang_module-compilation_context">compilation_context</a>, <a href="#swift_common.create_clang_module-module_map">module_map</a>, <a href="#swift_common.create_clang_module-precompiled_module">precompiled_module</a>)
</pre>

Creates a value representing a Clang module used as a Swift dependency.

Note: The `compilation_context` argument of this function is primarily
intended to communicate information *to* the Swift build rules, not to
retrieve information *back out.* In most cases, it is better to depend on
the `CcInfo` provider propagated by a Swift target to collect transitive
C/Objective-C compilation information about that target. This is because the
context used when compiling the module itself may not be the same as the
context desired when depending on it. (For example, `apple_common.Objc`
supports "strict include paths" which are only propagated to direct
dependents.)

One valid exception to the guidance above is retrieving the generated header
associated with a specific Swift module. Since the `CcInfo` provider
propagated by the library will have already merged them transitively (or,
in the case of a hypothetical custom rule that propagates multiple direct
modules, the `direct_public_headers` of the `CcInfo` would also have them
merged), it is acceptable to read the headers from the compilation context
of the module struct itself in order to associate them with the module that
generated them.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.create_clang_module-compilation_context"></a>compilation_context |  A <code>CcCompilationContext</code> that contains the header files and other context (such as include paths, preprocessor defines, and so forth) needed to compile this module as an explicit module.   |  none |
| <a id="swift_common.create_clang_module-module_map"></a>module_map |  The text module map file that defines this module. This argument may be specified as a <code>File</code> or as a <code>string</code>; in the latter case, it is assumed to be the path to a file that cannot be provided as an action input because it is outside the workspace (for example, the module map for a module from an Xcode SDK).   |  none |
| <a id="swift_common.create_clang_module-precompiled_module"></a>precompiled_module |  A <code>File</code> representing the precompiled module (<code>.pcm</code> file) if one was emitted for the module. This may be <code>None</code> if no explicit module was built for the module; in that case, targets that depend on the module will fall back to the text module map and headers.   |  <code>None</code> |

**RETURNS**

A `struct` containing the `compilation_context`, `module_map`, and
  `precompiled_module` fields provided as arguments.


<a id="#swift_common.create_linking_context_from_compilation_outputs"></a>

## swift_common.create_linking_context_from_compilation_outputs

<pre>
swift_common.create_linking_context_from_compilation_outputs(<a href="#swift_common.create_linking_context_from_compilation_outputs-actions">actions</a>, <a href="#swift_common.create_linking_context_from_compilation_outputs-additional_inputs">additional_inputs</a>, <a href="#swift_common.create_linking_context_from_compilation_outputs-alwayslink">alwayslink</a>,
                                                             <a href="#swift_common.create_linking_context_from_compilation_outputs-compilation_outputs">compilation_outputs</a>,
                                                             <a href="#swift_common.create_linking_context_from_compilation_outputs-feature_configuration">feature_configuration</a>, <a href="#swift_common.create_linking_context_from_compilation_outputs-label">label</a>,
                                                             <a href="#swift_common.create_linking_context_from_compilation_outputs-linking_contexts">linking_contexts</a>, <a href="#swift_common.create_linking_context_from_compilation_outputs-module_context">module_context</a>, <a href="#swift_common.create_linking_context_from_compilation_outputs-name">name</a>,
                                                             <a href="#swift_common.create_linking_context_from_compilation_outputs-swift_toolchain">swift_toolchain</a>, <a href="#swift_common.create_linking_context_from_compilation_outputs-user_link_flags">user_link_flags</a>)
</pre>

Creates a linking context from the outputs of a Swift compilation.

On some platforms, this function will spawn additional post-compile actions
for the module in order to add their outputs to the linking context. For
example, if the toolchain that requires a "module-wrap" invocation to embed
the `.swiftmodule` into an object file for debugging purposes, or if it
extracts auto-linking information from the object files to generate a linker
command line parameters file, those actions will be created here.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.create_linking_context_from_compilation_outputs-actions"></a>actions |  The context's <code>actions</code> object.   |  none |
| <a id="swift_common.create_linking_context_from_compilation_outputs-additional_inputs"></a>additional_inputs |  A <code>list</code> of <code>File</code>s containing any additional files that are referenced by <code>user_link_flags</code> and therefore need to be propagated up to the linker.   |  <code>[]</code> |
| <a id="swift_common.create_linking_context_from_compilation_outputs-alwayslink"></a>alwayslink |  If True, any binary that depends on the providers returned by this function will link in all of the library's object files, even if some contain no symbols referenced by the binary.   |  <code>False</code> |
| <a id="swift_common.create_linking_context_from_compilation_outputs-compilation_outputs"></a>compilation_outputs |  A <code>CcCompilationOutputs</code> value containing the object files to link. Typically, this is the second tuple element in the value returned by <code>swift_common.compile</code>.   |  none |
| <a id="swift_common.create_linking_context_from_compilation_outputs-feature_configuration"></a>feature_configuration |  A feature configuration obtained from <code>swift_common.configure_features</code>.   |  none |
| <a id="swift_common.create_linking_context_from_compilation_outputs-label"></a>label |  The <code>Label</code> of the target being built. This is used as the owner of the linker inputs created for post-compile actions (if any), and the label's name component also determines the name of the artifact unless it is overridden by the <code>name</code> argument.   |  none |
| <a id="swift_common.create_linking_context_from_compilation_outputs-linking_contexts"></a>linking_contexts |  A <code>list</code> of <code>CcLinkingContext</code>s containing libraries from dependencies.   |  <code>[]</code> |
| <a id="swift_common.create_linking_context_from_compilation_outputs-module_context"></a>module_context |  The module context returned by <code>swift_common.compile</code> containing information about the Swift module that was compiled. Typically, this is the first tuple element in the value returned by <code>swift_common.compile</code>.   |  none |
| <a id="swift_common.create_linking_context_from_compilation_outputs-name"></a>name |  A string that is used to derive the name of the library or libraries linked by this function. If this is not provided or is a falsy value, the name component of the <code>label</code> argument is used.   |  <code>None</code> |
| <a id="swift_common.create_linking_context_from_compilation_outputs-swift_toolchain"></a>swift_toolchain |  The <code>SwiftToolchainInfo</code> provider of the toolchain.   |  none |
| <a id="swift_common.create_linking_context_from_compilation_outputs-user_link_flags"></a>user_link_flags |  A <code>list</code> of strings containing additional flags that will be passed to the linker for any binary that links with the returned linking context.   |  <code>[]</code> |

**RETURNS**

A tuple of `(CcLinkingContext, CcLinkingOutputs)` containing the linking
  context to be propagated by the caller's `CcInfo` provider and the
  artifact representing the library that was linked, respectively.


<a id="#swift_common.create_module"></a>

## swift_common.create_module

<pre>
swift_common.create_module(<a href="#swift_common.create_module-name">name</a>, <a href="#swift_common.create_module-clang">clang</a>, <a href="#swift_common.create_module-is_system">is_system</a>, <a href="#swift_common.create_module-swift">swift</a>)
</pre>

Creates a value containing Clang/Swift module artifacts of a dependency.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.create_module-name"></a>name |  The name of the module.   |  none |
| <a id="swift_common.create_module-clang"></a>clang |  A value returned by <code>swift_common.create_clang_module</code> that contains artifacts related to Clang modules, such as a module map or precompiled module. This may be <code>None</code> if the module is a pure Swift module with no generated Objective-C interface.   |  <code>None</code> |
| <a id="swift_common.create_module-is_system"></a>is_system |  Indicates whether the module is a system module. The default value is <code>False</code>. System modules differ slightly from non-system modules in the way that they are passed to the compiler. For example, non-system modules have their Clang module maps passed to the compiler in both implicit and explicit module builds. System modules, on the other hand, do not have their module maps passed to the compiler in implicit module builds because there is currently no way to indicate that modules declared in a file passed via <code>-fmodule-map-file</code> should be treated as system modules even if they aren't declared with the <code>[system]</code> attribute, and some system modules may not build cleanly with respect to warnings otherwise. Therefore, it is assumed that any module with <code>is_system == True</code> must be able to be found using import search paths in order for implicit module builds to succeed.   |  <code>False</code> |
| <a id="swift_common.create_module-swift"></a>swift |  A value returned by <code>swift_common.create_swift_module</code> that contains artifacts related to Swift modules, such as the <code>.swiftmodule</code>, <code>.swiftdoc</code>, and/or <code>.swiftinterface</code> files emitted by the compiler. This may be <code>None</code> if the module is a pure C/Objective-C module.   |  <code>None</code> |

**RETURNS**

A `struct` containing the `name`, `clang`, `is_system`, and `swift`
  fields provided as arguments.


<a id="#swift_common.create_swift_info"></a>

## swift_common.create_swift_info

<pre>
swift_common.create_swift_info(<a href="#swift_common.create_swift_info-direct_swift_infos">direct_swift_infos</a>, <a href="#swift_common.create_swift_info-modules">modules</a>, <a href="#swift_common.create_swift_info-swift_infos">swift_infos</a>)
</pre>

Creates a new `SwiftInfo` provider with the given values.

This function is recommended instead of directly creating a `SwiftInfo`
provider because it encodes reasonable defaults for fields that some rules
may not be interested in and ensures that the direct and transitive fields
are set consistently.

This function can also be used to do a simple merge of `SwiftInfo`
providers, by leaving the `modules` argument unspecified. In that case, the
returned provider will not represent a true Swift module; it is merely a
"collector" for other dependencies.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.create_swift_info-direct_swift_infos"></a>direct_swift_infos |  A list of <code>SwiftInfo</code> providers from dependencies whose direct modules should be treated as direct modules in the resulting provider, in addition to their transitive modules being merged.   |  <code>[]</code> |
| <a id="swift_common.create_swift_info-modules"></a>modules |  A list of values (as returned by <code>swift_common.create_module</code>) that represent Clang and/or Swift module artifacts that are direct outputs of the target being built.   |  <code>[]</code> |
| <a id="swift_common.create_swift_info-swift_infos"></a>swift_infos |  A list of <code>SwiftInfo</code> providers from dependencies whose transitive modules should be merged into the resulting provider.   |  <code>[]</code> |

**RETURNS**

A new `SwiftInfo` provider with the given values.


<a id="#swift_common.create_swift_interop_info"></a>

## swift_common.create_swift_interop_info

<pre>
swift_common.create_swift_interop_info(<a href="#swift_common.create_swift_interop_info-module_map">module_map</a>, <a href="#swift_common.create_swift_interop_info-module_name">module_name</a>, <a href="#swift_common.create_swift_interop_info-requested_features">requested_features</a>, <a href="#swift_common.create_swift_interop_info-swift_infos">swift_infos</a>,
                                       <a href="#swift_common.create_swift_interop_info-unsupported_features">unsupported_features</a>)
</pre>

Returns a provider that lets a target expose C/Objective-C APIs to Swift.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.create_swift_interop_info-module_map"></a>module_map |  A <code>File</code> representing an existing module map that should be used to represent the module, or <code>None</code> (the default) if the module map should be generated based on the headers in the target's compilation context. If this argument is provided, then <code>module_name</code> must also be provided.   |  <code>None</code> |
| <a id="swift_common.create_swift_interop_info-module_name"></a>module_name |  A string denoting the name of the module, or <code>None</code> (the default) if the name should be derived automatically from the target label.   |  <code>None</code> |
| <a id="swift_common.create_swift_interop_info-requested_features"></a>requested_features |  A list of features (empty by default) that should be requested for the target, which are added to those supplied in the <code>features</code> attribute of the target. These features will be enabled unless they are otherwise marked as unsupported (either on the target or by the toolchain). This allows the rule implementation to have additional control over features that should be supported by default for all instances of that rule as if it were creating the feature configuration itself; for example, a rule can request that <code>swift.emit_c_module</code> always be enabled for its targets even if it is not explicitly enabled in the toolchain or on the target directly.   |  <code>[]</code> |
| <a id="swift_common.create_swift_interop_info-swift_infos"></a>swift_infos |  A list of <code>SwiftInfo</code> providers from dependencies, which will be merged with the new <code>SwiftInfo</code> created by the aspect.   |  <code>[]</code> |
| <a id="swift_common.create_swift_interop_info-unsupported_features"></a>unsupported_features |  A list of features (empty by default) that should be considered unsupported for the target, which are added to those supplied as negations in the <code>features</code> attribute. This allows the rule implementation to have additional control over features that should be disabled by default for all instances of that rule as if it were creating the feature configuration itself; for example, a rule that processes frameworks with headers that do not follow strict layering can request that <code>swift.strict_module</code> always be disabled for its targets even if it is enabled by default in the toolchain.   |  <code>[]</code> |

**RETURNS**

A provider whose type/layout is an implementation detail and should not
  be relied upon.


<a id="#swift_common.create_swift_module"></a>

## swift_common.create_swift_module

<pre>
swift_common.create_swift_module(<a href="#swift_common.create_swift_module-swiftdoc">swiftdoc</a>, <a href="#swift_common.create_swift_module-swiftmodule">swiftmodule</a>, <a href="#swift_common.create_swift_module-defines">defines</a>, <a href="#swift_common.create_swift_module-swiftsourceinfo">swiftsourceinfo</a>, <a href="#swift_common.create_swift_module-swiftinterface">swiftinterface</a>)
</pre>

Creates a value representing a Swift module use as a Swift dependency.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.create_swift_module-swiftdoc"></a>swiftdoc |  The <code>.swiftdoc</code> file emitted by the compiler for this module.   |  none |
| <a id="swift_common.create_swift_module-swiftmodule"></a>swiftmodule |  The <code>.swiftmodule</code> file emitted by the compiler for this module.   |  none |
| <a id="swift_common.create_swift_module-defines"></a>defines |  A list of defines that will be provided as <code>copts</code> to targets that depend on this module. If omitted, the empty list will be used.   |  <code>[]</code> |
| <a id="swift_common.create_swift_module-swiftsourceinfo"></a>swiftsourceinfo |  The <code>.swiftsourceinfo</code> file emitted by the compiler for this module. May be <code>None</code> if no source info file was emitted.   |  <code>None</code> |
| <a id="swift_common.create_swift_module-swiftinterface"></a>swiftinterface |  The <code>.swiftinterface</code> file emitted by the compiler for this module. May be <code>None</code> if no module interface file was emitted.   |  <code>None</code> |

**RETURNS**

A `struct` containing the `defines`, `swiftdoc`, `swiftmodule`, and
  `swiftinterface` fields provided as arguments.


<a id="#swift_common.derive_module_name"></a>

## swift_common.derive_module_name

<pre>
swift_common.derive_module_name(<a href="#swift_common.derive_module_name-args">args</a>)
</pre>

Returns a derived module name from the given build label.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.derive_module_name-args"></a>args |  Either a single argument of type <code>Label</code>, or two arguments of type <code>str</code> where the first argument is the package name and the second argument is the target name.   |  none |

**RETURNS**

The module name derived from the label.


<a id="#swift_common.is_enabled"></a>

## swift_common.is_enabled

<pre>
swift_common.is_enabled(<a href="#swift_common.is_enabled-feature_configuration">feature_configuration</a>, <a href="#swift_common.is_enabled-feature_name">feature_name</a>)
</pre>

Returns `True` if the feature is enabled in the feature configuration.

This function handles both Swift-specific features and C++ features so that
users do not have to manually extract the C++ configuration in order to
check it.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.is_enabled-feature_configuration"></a>feature_configuration |  The Swift feature configuration, as returned by <code>swift_common.configure_features</code>.   |  none |
| <a id="swift_common.is_enabled-feature_name"></a>feature_name |  The name of the feature to check.   |  none |

**RETURNS**

`True` if the given feature is enabled in the feature configuration.


<a id="#swift_common.library_rule_attrs"></a>

## swift_common.library_rule_attrs

<pre>
swift_common.library_rule_attrs(<a href="#swift_common.library_rule_attrs-additional_deps_aspects">additional_deps_aspects</a>, <a href="#swift_common.library_rule_attrs-requires_srcs">requires_srcs</a>)
</pre>

Returns an attribute dictionary for `swift_library`-like rules.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.library_rule_attrs-additional_deps_aspects"></a>additional_deps_aspects |  A list of additional aspects that should be applied to <code>deps</code>. Defaults to the empty list. These must be passed by the individual rules to avoid potential circular dependencies between the API and the aspects; the API loaded the aspects directly, then those aspects would not be able to load the API.   |  <code>[]</code> |
| <a id="swift_common.library_rule_attrs-requires_srcs"></a>requires_srcs |  Indicates whether the <code>srcs</code> attribute should be marked as mandatory and non-empty. Defaults to <code>True</code>.   |  <code>True</code> |

**RETURNS**

A new attribute dictionary that can be added to the attributes of a
  custom build rule to provide the same interface as `swift_library`.


<a id="#swift_common.precompile_clang_module"></a>

## swift_common.precompile_clang_module

<pre>
swift_common.precompile_clang_module(<a href="#swift_common.precompile_clang_module-actions">actions</a>, <a href="#swift_common.precompile_clang_module-cc_compilation_context">cc_compilation_context</a>, <a href="#swift_common.precompile_clang_module-feature_configuration">feature_configuration</a>,
                                     <a href="#swift_common.precompile_clang_module-module_map_file">module_map_file</a>, <a href="#swift_common.precompile_clang_module-module_name">module_name</a>, <a href="#swift_common.precompile_clang_module-swift_toolchain">swift_toolchain</a>, <a href="#swift_common.precompile_clang_module-target_name">target_name</a>,
                                     <a href="#swift_common.precompile_clang_module-swift_infos">swift_infos</a>)
</pre>

Precompiles an explicit Clang module that is compatible with Swift.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.precompile_clang_module-actions"></a>actions |  The context's <code>actions</code> object.   |  none |
| <a id="swift_common.precompile_clang_module-cc_compilation_context"></a>cc_compilation_context |  A <code>CcCompilationContext</code> that contains headers and other information needed to compile this module. This compilation context should contain all headers required to compile the module, which includes the headers for the module itself *and* any others that must be present on the file system/in the sandbox for compilation to succeed. The latter typically refers to the set of headers of the direct dependencies of the module being compiled, which Clang needs to be physically present before it detects that they belong to one of the precompiled module dependencies.   |  none |
| <a id="swift_common.precompile_clang_module-feature_configuration"></a>feature_configuration |  A feature configuration obtained from <code>swift_common.configure_features</code>.   |  none |
| <a id="swift_common.precompile_clang_module-module_map_file"></a>module_map_file |  A textual module map file that defines the Clang module to be compiled.   |  none |
| <a id="swift_common.precompile_clang_module-module_name"></a>module_name |  The name of the top-level module in the module map that will be compiled.   |  none |
| <a id="swift_common.precompile_clang_module-swift_toolchain"></a>swift_toolchain |  The <code>SwiftToolchainInfo</code> provider of the toolchain.   |  none |
| <a id="swift_common.precompile_clang_module-target_name"></a>target_name |  The name of the target for which the code is being compiled, which is used to determine unique file paths for the outputs.   |  none |
| <a id="swift_common.precompile_clang_module-swift_infos"></a>swift_infos |  A list of <code>SwiftInfo</code> providers representing dependencies required to compile this module.   |  <code>[]</code> |

**RETURNS**

A `File` representing the precompiled module (`.pcm`) file, or `None` if
  the toolchain or target does not support precompiled modules.


<a id="#swift_common.toolchain_attrs"></a>

## swift_common.toolchain_attrs

<pre>
swift_common.toolchain_attrs(<a href="#swift_common.toolchain_attrs-toolchain_attr_name">toolchain_attr_name</a>)
</pre>

Returns an attribute dictionary for toolchain users.

The returned dictionary contains a key with the name specified by the
argument `toolchain_attr_name` (which defaults to the value `"_toolchain"`),
the value of which is a BUILD API `attr.label` that references the default
Swift toolchain. Users who are authoring custom rules can add this
dictionary to the attributes of their own rule in order to depend on the
toolchain and access its `SwiftToolchainInfo` provider to pass it to other
`swift_common` functions.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="swift_common.toolchain_attrs-toolchain_attr_name"></a>toolchain_attr_name |  The name of the attribute that should be created that points to the toolchain. This defaults to <code>_toolchain</code>, which is sufficient for most rules; it is customizable for certain aspects where having an attribute with the same name but different values applied to a particular target causes a build crash.   |  <code>"_toolchain"</code> |

**RETURNS**

A new attribute dictionary that can be added to the attributes of a
  custom build rule to provide access to the Swift toolchain.



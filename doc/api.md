# Build API

<!-- Generated file, do not edit directly. -->



The `swift_common` module provides API access to the behavior implemented
by the Swift build rules, so that other custom rules can invoke Swift
compilation and/or linking as part of their implementation.

On this page:

  * [swift_common.cc_feature_configuration](#swift_common.cc_feature_configuration)
  * [swift_common.compilation_attrs](#swift_common.compilation_attrs)
  * [swift_common.compile](#swift_common.compile)
  * [swift_common.configure_features](#swift_common.configure_features)
  * [swift_common.create_clang_module](#swift_common.create_clang_module)
  * [swift_common.create_module](#swift_common.create_module)
  * [swift_common.create_swift_info](#swift_common.create_swift_info)
  * [swift_common.create_swift_module](#swift_common.create_swift_module)
  * [swift_common.derive_module_name](#swift_common.derive_module_name)
  * [swift_common.get_implicit_deps](#swift_common.get_implicit_deps)
  * [swift_common.is_enabled](#swift_common.is_enabled)
  * [swift_common.library_rule_attrs](#swift_common.library_rule_attrs)
  * [swift_common.precompile_clang_module](#swift_common.precompile_clang_module)
  * [swift_common.swift_clang_module_aspect](#swift_common.swift_clang_module_aspect)
  * [swift_common.swift_runtime_linkopts](#swift_common.swift_runtime_linkopts)
  * [swift_common.toolchain_attrs](#swift_common.toolchain_attrs)

<a name="swift_common.cc_feature_configuration"></a>
## swift_common.cc_feature_configuration

<pre style="white-space: normal">
swift_common.cc_feature_configuration(<a href="#swift_common.cc_feature_configuration.feature_configuration">feature_configuration</a>)
</pre>

Returns the C++ feature configuration in a Swift feature configuration.

<a name="swift_common.cc_feature_configuration.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.cc_feature_configuration.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Required</code></p><p>The Swift feature configuration, as returned from
<code>swift_common.configure_features</code>.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.cc_feature_configuration.returns"></a>
### Returns

A C++ `FeatureConfiguration` value (see
[`cc_common.configure_features`](https://docs.bazel.build/versions/master/skylark/lib/cc_common.html#configure_features)
for more information).

<a name="swift_common.compilation_attrs"></a>
## swift_common.compilation_attrs

<pre style="white-space: normal">
swift_common.compilation_attrs(<a href="#swift_common.compilation_attrs.additional_deps_aspects">additional_deps_aspects</a>=[])
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

<a name="swift_common.compilation_attrs.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.compilation_attrs.additional_deps_aspects">
      <td><code>additional_deps_aspects</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of additional aspects that should be
applied to <code>deps</code>. Defaults to the empty list. These must be passed
by the individual rules to avoid potential circular dependencies
between the API and the aspects; the API loaded the aspects
directly, then those aspects would not be able to load the API.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.compilation_attrs.returns"></a>
### Returns

A new attribute dictionary that can be added to the attributes of a
custom build rule to provide a similar interface to `swift_binary`,
`swift_library`, and `swift_test`.

<a name="swift_common.compile"></a>
## swift_common.compile

<pre style="white-space: normal">
swift_common.compile(*, <a href="#swift_common.compile.actions">actions</a>, <a href="#swift_common.compile.feature_configuration">feature_configuration</a>, <a href="#swift_common.compile.module_name">module_name</a>, <a href="#swift_common.compile.srcs">srcs</a>, <a href="#swift_common.compile.swift_toolchain">swift_toolchain</a>,
<a href="#swift_common.compile.target_name">target_name</a>, <a href="#swift_common.compile.additional_inputs">additional_inputs</a>=[], <a href="#swift_common.compile.bin_dir">bin_dir</a>=None, <a href="#swift_common.compile.copts">copts</a>=[], <a href="#swift_common.compile.defines">defines</a>=[], <a href="#swift_common.compile.deps">deps</a>=[],
<a href="#swift_common.compile.generated_header_name">generated_header_name</a>=None, <a href="#swift_common.compile.genfiles_dir">genfiles_dir</a>=None)
</pre>

Compiles a Swift module.

<a name="swift_common.compile.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.compile.actions">
      <td><code>actions</code></td>
      <td><p><code>Required</code></p><p>The context's <code>actions</code> object.</p></td>
    </tr>
    <tr id="swift_common.compile.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Required</code></p><p>A feature configuration obtained from
<code>swift_common.configure_features</code>.</p></td>
    </tr>
    <tr id="swift_common.compile.module_name">
      <td><code>module_name</code></td>
      <td><p><code>Required</code></p><p>The name of the Swift module being compiled. This must be
present and valid; use <code>swift_common.derive_module_name</code> to generate
a default from the target's label if needed.</p></td>
    </tr>
    <tr id="swift_common.compile.srcs">
      <td><code>srcs</code></td>
      <td><p><code>Required</code></p><p>The Swift source files to compile.</p></td>
    </tr>
    <tr id="swift_common.compile.swift_toolchain">
      <td><code>swift_toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain.</p></td>
    </tr>
    <tr id="swift_common.compile.target_name">
      <td><code>target_name</code></td>
      <td><p><code>Required</code></p><p>The name of the target for which the code is being
compiled, which is used to determine unique file paths for the
outputs.</p></td>
    </tr>
    <tr id="swift_common.compile.additional_inputs">
      <td><code>additional_inputs</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>File</code>s representing additional input files
that need to be passed to the Swift compile action because they are
referenced by compiler flags.</p></td>
    </tr>
    <tr id="swift_common.compile.bin_dir">
      <td><code>bin_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-bin</code> directory root. If provided, its path is used
to store the cache for modules precompiled by Swift's ClangImporter,
and it is added to ClangImporter's header search paths for
compatibility with Bazel's C++ and Objective-C rules which support
includes of generated headers from that location.</p></td>
    </tr>
    <tr id="swift_common.compile.copts">
      <td><code>copts</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of compiler flags that apply to the target being built.
These flags, along with those from Bazel's Swift configuration
fragment (i.e., <code>--swiftcopt</code> command line flags) are scanned to
determine whether whole module optimization is being requested,
which affects the nature of the output files.</p></td>
    </tr>
    <tr id="swift_common.compile.defines">
      <td><code>defines</code></td>
      <td><p><code>Optional; default is []</code></p><p>Symbols that should be defined by passing <code>-D</code> to the compiler.</p></td>
    </tr>
    <tr id="swift_common.compile.deps">
      <td><code>deps</code></td>
      <td><p><code>Optional; default is []</code></p><p>Dependencies of the target being compiled. These targets must
propagate one of the following providers: <code>CcInfo</code>, <code>SwiftInfo</code>, or
<code>apple_common.Objc</code>.</p></td>
    </tr>
    <tr id="swift_common.compile.generated_header_name">
      <td><code>generated_header_name</code></td>
      <td><p><code>Optional; default is None</code></p><p>The name of the Objective-C generated header that
should be generated for this module. If omitted, the name
<code>${target_name}-Swift.h</code> will be used.</p></td>
    </tr>
    <tr id="swift_common.compile.genfiles_dir">
      <td><code>genfiles_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-genfiles</code> directory root. If provided, its
path is added to ClangImporter's header search paths for
compatibility with Bazel's C++ and Objective-C rules which support
inclusions of generated headers from that location.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.compile.returns"></a>
### Returns

A `struct` containing the following fields:

*   `generated_header`: A `File` representing the Objective-C header
    that was generated for the compiled module. If no header was
    generated, this field will be None.
*   `generated_header_module_map`: A `File` representing the module map
    that was generated to correspond to the generated Objective-C
    header. If no module map was generated, this field will be None.
*   `indexstore`: A `File` representing the directory that contains the
    index store data generated by the compiler if index-while-building
    is enabled. May be None if no indexing was requested.
*   `linker_flags`: A list of strings representing additional flags that
    should be passed to the linker when linking these objects into a
    binary. If there are none, this field will always be an empty list,
    never None.
*   `linker_inputs`: A list of `File`s representing additional input
    files (such as those referenced in `linker_flags`) that need to be
    available to the link action when linking these objects into a
    binary. If there are none, this field will always be an empty list,
    never None.
*   `object_files`: A list of `.o` files that were produced by the
    compiler.
*   `stats_directory`: A `File` representing the directory that contains
    the timing statistics emitted by the compiler. If no stats were
    requested, this field will be None.
*   `swiftdoc`: The `.swiftdoc` file that was produced by the compiler.
*   `swiftinterface`: The `.swiftinterface` file that was produced by
    the compiler. If no interface file was produced (because the
    toolchain does not support them or it was not requested), this field
    will be None.
*   `swiftmodule`: The `.swiftmodule` file that was produced by the
    compiler.

<a name="swift_common.configure_features"></a>
## swift_common.configure_features

<pre style="white-space: normal">
swift_common.configure_features(<a href="#swift_common.configure_features.ctx">ctx</a>, <a href="#swift_common.configure_features.swift_toolchain">swift_toolchain</a>, *, <a href="#swift_common.configure_features.requested_features">requested_features</a>=[],
<a href="#swift_common.configure_features.unsupported_features">unsupported_features</a>=[])
</pre>

Creates a feature configuration to be passed to Swift build APIs.

This function calls through to `cc_common.configure_features` to configure
underlying C++ features as well, and nests the C++ feature configuration
inside the Swift one. Users who need to call C++ APIs that require a feature
configuration can extract it by calling
`swift_common.cc_feature_configuration(feature_configuration)`.

<a name="swift_common.configure_features.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.configure_features.ctx">
      <td><code>ctx</code></td>
      <td><p><code>Required</code></p><p>The rule context.</p></td>
    </tr>
    <tr id="swift_common.configure_features.swift_toolchain">
      <td><code>swift_toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain
being used to build. The C++ toolchain associated with the Swift
toolchain is used to create the underlying C++ feature
configuration.</p></td>
    </tr>
    <tr id="swift_common.configure_features.requested_features">
      <td><code>requested_features</code></td>
      <td><p><code>Optional; default is []</code></p><p>The list of features to be enabled. This is
typically obtained using the <code>ctx.features</code> field in a rule
implementation function.</p></td>
    </tr>
    <tr id="swift_common.configure_features.unsupported_features">
      <td><code>unsupported_features</code></td>
      <td><p><code>Optional; default is []</code></p><p>The list of features that are unsupported by the
current rule. This is typically obtained using the
<code>ctx.disabled_features</code> field in a rule implementation function.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.configure_features.returns"></a>
### Returns

An opaque value representing the feature configuration that can be
passed to other `swift_common` functions.

<a name="swift_common.create_clang_module"></a>
## swift_common.create_clang_module

<pre style="white-space: normal">
swift_common.create_clang_module(*, <a href="#swift_common.create_clang_module.compilation_context">compilation_context</a>, <a href="#swift_common.create_clang_module.module_map">module_map</a>, <a href="#swift_common.create_clang_module.precompiled_module">precompiled_module</a>=None)
</pre>

Creates a value representing a Clang module used as a Swift dependency.

<a name="swift_common.create_clang_module.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.create_clang_module.compilation_context">
      <td><code>compilation_context</code></td>
      <td><p><code>Required</code></p><p>A <code>CcCompilationContext</code> that contains the header
files, include paths, and other context necessary to compile targets
that depend on this module (if using the text module map instead of
the precompiled module).</p></td>
    </tr>
    <tr id="swift_common.create_clang_module.module_map">
      <td><code>module_map</code></td>
      <td><p><code>Required</code></p><p>A <code>File</code> representing the text module map file that defines
this module.</p></td>
    </tr>
    <tr id="swift_common.create_clang_module.precompiled_module">
      <td><code>precompiled_module</code></td>
      <td><p><code>Optional; default is None</code></p><p>A <code>File</code> representing the precompiled module (<code>.pcm</code>
file) if one was emitted for the module. This may be <code>None</code> if no
explicit module was built for the module; in that case, targets that
depend on the module will fall back to the text module map and
headers.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.create_clang_module.returns"></a>
### Returns

A `struct` containing the `compilation_context`, `module_map`, and
`precompiled_module` fields provided as arguments.

<a name="swift_common.create_module"></a>
## swift_common.create_module

<pre style="white-space: normal">
swift_common.create_module(<a href="#swift_common.create_module.name">name</a>, *, <a href="#swift_common.create_module.clang">clang</a>=None, <a href="#swift_common.create_module.swift">swift</a>=None)
</pre>

Creates a value containing Clang/Swift module artifacts of a dependency.

At least one of the `clang` and `swift` arguments must not be `None`. It is
valid for both to be present; this is the case for most Swift modules, which
provide both Swift module artifacts as well as a generated header/module map
for Objective-C targets to depend on.

<a name="swift_common.create_module.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.create_module.name">
      <td><code>name</code></td>
      <td><p><code>Required</code></p><p>The name of the module.</p></td>
    </tr>
    <tr id="swift_common.create_module.clang">
      <td><code>clang</code></td>
      <td><p><code>Optional; default is None</code></p><p>A value returned by <code>swift_common.create_clang_module</code> that
contains artifacts related to Clang modules, such as a module map or
precompiled module. This may be <code>None</code> if the module is a pure Swift
module with no generated Objective-C interface.</p></td>
    </tr>
    <tr id="swift_common.create_module.swift">
      <td><code>swift</code></td>
      <td><p><code>Optional; default is None</code></p><p>A value returned by <code>swift_common.create_swift_module</code> that
contains artifacts related to Swift modules, such as the
<code>.swiftmodule</code>, <code>.swiftdoc</code>, and/or <code>.swiftinterface</code> files emitted
by the compiler. This may be <code>None</code> if the module is a pure
C/Objective-C module.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.create_module.returns"></a>
### Returns

A `struct` containing the `name`, `clang`, and `swift` fields provided
as arguments.

<a name="swift_common.create_swift_info"></a>
## swift_common.create_swift_info

<pre style="white-space: normal">
swift_common.create_swift_info(*, <a href="#swift_common.create_swift_info.module_name">module_name</a>=None, <a href="#swift_common.create_swift_info.modules">modules</a>=[], <a href="#swift_common.create_swift_info.swift_infos">swift_infos</a>=[], <a href="#swift_common.create_swift_info.swift_version">swift_version</a>=None)
</pre>

Creates a new `SwiftInfo` provider with the given values.

This function is recommended instead of directly creating a `SwiftInfo`
provider because it encodes reasonable defaults for fields that some rules
may not be interested in and ensures that the direct and transitive fields
are set consistently.

This function can also be used to do a simple merge of `SwiftInfo`
providers, by leaving all of the arguments except for `swift_infos` as their
empty defaults. In that case, the returned provider will not represent a
true Swift module; it is merely a "collector" for other dependencies.

<a name="swift_common.create_swift_info.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.create_swift_info.module_name">
      <td><code>module_name</code></td>
      <td><p><code>Optional; default is None</code></p><p>This argument is deprecated. The module name(s) should be
specified in the values passed to the <code>modules</code> argument.</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.modules">
      <td><code>modules</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of values (as returned by <code>swift_common.create_module</code>)
that represent Clang and/or Swift module artifacts that are direct
outputs of the target being built.</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.swift_infos">
      <td><code>swift_infos</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>SwiftInfo</code> providers from dependencies, whose
transitive fields should be merged into the new one. If omitted, no
transitive data is collected.</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.swift_version">
      <td><code>swift_version</code></td>
      <td><p><code>Optional; default is None</code></p><p>A string containing the value of the <code>-swift-version</code>
flag used when compiling this target, or <code>None</code> (the default) if it
was not set or is not relevant.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.create_swift_info.returns"></a>
### Returns

A new `SwiftInfo` provider with the given values.

<a name="swift_common.create_swift_module"></a>
## swift_common.create_swift_module

<pre style="white-space: normal">
swift_common.create_swift_module(*, <a href="#swift_common.create_swift_module.swiftdoc">swiftdoc</a>, <a href="#swift_common.create_swift_module.swiftmodule">swiftmodule</a>, <a href="#swift_common.create_swift_module.defines">defines</a>=[], <a href="#swift_common.create_swift_module.swiftinterface">swiftinterface</a>=None)
</pre>

Creates a value representing a Swift module use as a Swift dependency.

<a name="swift_common.create_swift_module.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.create_swift_module.swiftdoc">
      <td><code>swiftdoc</code></td>
      <td><p><code>Required</code></p><p>The <code>.swiftdoc</code> file emitted by the compiler for this module.</p></td>
    </tr>
    <tr id="swift_common.create_swift_module.swiftmodule">
      <td><code>swiftmodule</code></td>
      <td><p><code>Required</code></p><p>The <code>.swiftmodule</code> file emitted by the compiler for this
module.</p></td>
    </tr>
    <tr id="swift_common.create_swift_module.defines">
      <td><code>defines</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of defines that will be provided as <code>copts</code> to targets
that depend on this module. If omitted, the empty list will be used.</p></td>
    </tr>
    <tr id="swift_common.create_swift_module.swiftinterface">
      <td><code>swiftinterface</code></td>
      <td><p><code>Optional; default is None</code></p><p>The <code>.swiftinterface</code> file emitted by the compiler for
this module. May be <code>None</code> if no module interface file was emitted.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.create_swift_module.returns"></a>
### Returns

A `struct` containing the `defines`, `swiftdoc`, `swiftmodule`, and
`swiftinterface` fields provided as arguments.

<a name="swift_common.derive_module_name"></a>
## swift_common.derive_module_name

<pre style="white-space: normal">
swift_common.derive_module_name(<a href="#swift_common.derive_module_name.*args">*args</a>)
</pre>

Returns a derived module name from the given build label.

For targets whose module name is not explicitly specified, the module name
is computed by creating an underscore-delimited string from the components
of the label, replacing any non-identifier characters also with underscores.

This mapping is not intended to be reversible.

<a name="swift_common.derive_module_name.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.derive_module_name.*args">
      <td><code>*args</code></td>
      <td><p>Either a single argument of type <code>Label</code>, or two arguments of
type <code>str</code> where the first argument is the package name and the
second argument is the target name.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.derive_module_name.returns"></a>
### Returns

The module name derived from the label.

<a name="swift_common.get_implicit_deps"></a>
## swift_common.get_implicit_deps

<pre style="white-space: normal">
swift_common.get_implicit_deps(<a href="#swift_common.get_implicit_deps.feature_configuration">feature_configuration</a>, <a href="#swift_common.get_implicit_deps.swift_toolchain">swift_toolchain</a>)
</pre>

Gets the list of implicit dependencies from the toolchain.

<a name="swift_common.get_implicit_deps.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.get_implicit_deps.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Required</code></p><p>The feature configuration, which determines
whether optional implicit dependencies are included.</p></td>
    </tr>
    <tr id="swift_common.get_implicit_deps.swift_toolchain">
      <td><code>swift_toolchain</code></td>
      <td><p><code>Required</code></p><p>The Swift toolchain.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.get_implicit_deps.returns"></a>
### Returns

A list of targets that should be treated as implicit dependencies of
the toolchain under the given feature configuration.

<a name="swift_common.is_enabled"></a>
## swift_common.is_enabled

<pre style="white-space: normal">
swift_common.is_enabled(<a href="#swift_common.is_enabled.feature_configuration">feature_configuration</a>, <a href="#swift_common.is_enabled.feature_name">feature_name</a>)
</pre>

Returns `True` if the feature is enabled in the feature configuration.

This function handles both Swift-specific features and C++ features so that
users do not have to manually extract the C++ configuration in order to
check it.

<a name="swift_common.is_enabled.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.is_enabled.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Required</code></p><p>The Swift feature configuration, as returned by
<code>swift_common.configure_features</code>.</p></td>
    </tr>
    <tr id="swift_common.is_enabled.feature_name">
      <td><code>feature_name</code></td>
      <td><p><code>Required</code></p><p>The name of the feature to check.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.is_enabled.returns"></a>
### Returns

`True` if the given feature is enabled in the feature configuration.

<a name="swift_common.library_rule_attrs"></a>
## swift_common.library_rule_attrs

<pre style="white-space: normal">
swift_common.library_rule_attrs(<a href="#swift_common.library_rule_attrs.additional_deps_aspects">additional_deps_aspects</a>=[])
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

<a name="swift_common.library_rule_attrs.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.library_rule_attrs.additional_deps_aspects">
      <td><code>additional_deps_aspects</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of additional aspects that should be
applied to <code>deps</code>. Defaults to the empty list. These must be passed
by the individual rules to avoid potential circular dependencies
between the API and the aspects; the API loaded the aspects
directly, then those aspects would not be able to load the API.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.library_rule_attrs.returns"></a>
### Returns

A new attribute dictionary that can be added to the attributes of a
custom build rule to provide the same interface as `swift_library`.

<a name="swift_common.precompile_clang_module"></a>
## swift_common.precompile_clang_module

<pre style="white-space: normal">
swift_common.precompile_clang_module(*, <a href="#swift_common.precompile_clang_module.actions">actions</a>, <a href="#swift_common.precompile_clang_module.cc_compilation_context">cc_compilation_context</a>, <a href="#swift_common.precompile_clang_module.feature_configuration">feature_configuration</a>,
<a href="#swift_common.precompile_clang_module.module_map_file">module_map_file</a>, <a href="#swift_common.precompile_clang_module.module_name">module_name</a>, <a href="#swift_common.precompile_clang_module.swift_toolchain">swift_toolchain</a>, <a href="#swift_common.precompile_clang_module.target_name">target_name</a>, <a href="#swift_common.precompile_clang_module.bin_dir">bin_dir</a>=None, <a href="#swift_common.precompile_clang_module.genfiles_dir">genfiles_dir</a>=None,
<a href="#swift_common.precompile_clang_module.swift_info">swift_info</a>=None)
</pre>

Precompiles an explicit Clang module that is compatible with Swift.

<a name="swift_common.precompile_clang_module.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.precompile_clang_module.actions">
      <td><code>actions</code></td>
      <td><p><code>Required</code></p><p>The context's <code>actions</code> object.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.cc_compilation_context">
      <td><code>cc_compilation_context</code></td>
      <td><p><code>Required</code></p><p>A <code>CcCompilationContext</code> that contains headers
and other information needed to compile this module. This
compilation context should contain all headers required to compile
the module, which includes the headers for the module itself <em>and</em>
any others that must be present on the file system/in the sandbox
for compilation to succeed. The latter typically refers to the set
of headers of the direct dependencies of the module being compiled,
which Clang needs to be physically present before it detects that
they belong to one of the precompiled module dependencies.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Required</code></p><p>A feature configuration obtained from
<code>swift_common.configure_features</code>.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.module_map_file">
      <td><code>module_map_file</code></td>
      <td><p><code>Required</code></p><p>A textual module map file that defines the Clang module
to be compiled.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.module_name">
      <td><code>module_name</code></td>
      <td><p><code>Required</code></p><p>The name of the top-level module in the module map that
will be compiled.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.swift_toolchain">
      <td><code>swift_toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.target_name">
      <td><code>target_name</code></td>
      <td><p><code>Required</code></p><p>The name of the target for which the code is being
compiled, which is used to determine unique file paths for the
outputs.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.bin_dir">
      <td><code>bin_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-bin</code> directory root. If provided, its path is used
to store the cache for modules precompiled by Swift's ClangImporter,
and it is added to ClangImporter's header search paths for
compatibility with Bazel's C++ and Objective-C rules which support
includes of generated headers from that location.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.genfiles_dir">
      <td><code>genfiles_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-genfiles</code> directory root. If provided, its
path is added to ClangImporter's header search paths for
compatibility with Bazel's C++ and Objective-C rules which support
inclusions of generated headers from that location.</p></td>
    </tr>
    <tr id="swift_common.precompile_clang_module.swift_info">
      <td><code>swift_info</code></td>
      <td><p><code>Optional; default is None</code></p><p>A <code>SwiftInfo</code> provider that contains dependencies required
to compile this module.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.precompile_clang_module.returns"></a>
### Returns

A `File` representing the precompiled module (`.pcm`) file, or `None` if
the toolchain or target does not support precompiled modules.


<a name="swift_common.swift_clang_module_aspect"></a>
## swift_common.swift_clang_module_aspect

<pre style="white-space: normal">
swift_common.swift_clang_module_aspect(<a href="#swift_common.swift_clang_module_aspect.name">name</a>)
</pre>

Propagates unified `SwiftInfo` providers for targets that represent
C/Objective-C modules.

This aspect unifies the propagation of Clang module artifacts so that Swift
targets that depend on C/Objective-C targets can find the necessary module
artifacts, and so that Swift module artifacts are not lost when passing through
a non-Swift target in the build graph (for example, a `swift_library` that
depends on an `objc_library` that depends on a `swift_library`).

It also manages module map generation for `cc_library` targets that have the
`swift_module` tag. This tag may take one of two forms:

    *   `swift_module`: By itself, this indicates that the target is compatible
        with Swift and should be given a module name that is derived from its
        target label.
    *   `swift_module=name`: The module should be given the name `name`.

Note that the public headers of such `cc_library` targets must be parsable as C,
since Swift does not support C++ interop at this time.

Most users will not need to interact directly with this aspect, since it is
automatically applied to the `deps` attribute of all `swift_binary`,
`swift_library`, and `swift_test` targets. However, some rules may need to
provide custom propagation logic of C/Objective-C module dependencies; for
example, a rule that has a support library as a private attribute would need to
ensure that `SwiftInfo` providers for that library and its dependencies are
propagated to any targets that depend on it, since they would not be propagated
via `deps`. In this case, the custom rule can attach this aspect to that support
library's attribute and then merge its `SwiftInfo` provider with any others that
it propagates for its targets.

<a name="swift_common.swift_clang_module_aspect.attributes"></a>
### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.swift_clang_module_aspect.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.swift_runtime_linkopts"></a>
## swift_common.swift_runtime_linkopts

<pre style="white-space: normal">
swift_common.swift_runtime_linkopts(<a href="#swift_common.swift_runtime_linkopts.is_static">is_static</a>, <a href="#swift_common.swift_runtime_linkopts.toolchain">toolchain</a>, <a href="#swift_common.swift_runtime_linkopts.is_test">is_test</a>=False)
</pre>

Returns the flags that should be passed when linking a Swift binary.

This function provides the appropriate linker arguments to callers who need
to link a binary using something other than `swift_binary` (for example, an
application bundle containing a universal `apple_binary`).

<a name="swift_common.swift_runtime_linkopts.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.swift_runtime_linkopts.is_static">
      <td><code>is_static</code></td>
      <td><p><code>Required</code></p><p>A <code>Boolean</code> value indicating whether the binary should be
linked against the static (rather than the dynamic) Swift runtime
libraries.</p></td>
    </tr>
    <tr id="swift_common.swift_runtime_linkopts.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain whose
linker options are desired.</p></td>
    </tr>
    <tr id="swift_common.swift_runtime_linkopts.is_test">
      <td><code>is_test</code></td>
      <td><p><code>Optional; default is False</code></p><p>A <code>Boolean</code> value indicating whether the target being linked is
a test target.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.swift_runtime_linkopts.returns"></a>
### Returns

A `list` of command line flags that should be passed when linking a
binary against the Swift runtime libraries.

<a name="swift_common.toolchain_attrs"></a>
## swift_common.toolchain_attrs

<pre style="white-space: normal">
swift_common.toolchain_attrs(<a href="#swift_common.toolchain_attrs.toolchain_attr_name">toolchain_attr_name</a>='_toolchain')
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

<a name="swift_common.toolchain_attrs.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.toolchain_attrs.toolchain_attr_name">
      <td><code>toolchain_attr_name</code></td>
      <td><p><code>Optional; default is '_toolchain'</code></p><p>The name of the attribute that should be created
that points to the toolchain. This defaults to <code>_toolchain</code>, which
is sufficient for most rules; it is customizable for certain aspects
where having an attribute with the same name but different values
applied to a particular target causes a build crash.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.toolchain_attrs.returns"></a>
### Returns

A new attribute dictionary that can be added to the attributes of a
custom build rule to provide access to the Swift toolchain.



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
  * [swift_common.create_swift_info](#swift_common.create_swift_info)
  * [swift_common.derive_module_name](#swift_common.derive_module_name)
  * [swift_common.is_enabled](#swift_common.is_enabled)
  * [swift_common.library_rule_attrs](#swift_common.library_rule_attrs)
  * [swift_common.swift_runtime_linkopts](#swift_common.swift_runtime_linkopts)
  * [swift_common.swiftc_command_line_and_inputs](#swift_common.swiftc_command_line_and_inputs)
  * [swift_common.toolchain_attrs](#swift_common.toolchain_attrs)

<a name="swift_common.cc_feature_configuration"></a>
## swift_common.cc_feature_configuration

<pre style="white-space: normal">
swift_common.cc_feature_configuration(<a href="#swift_common.cc_feature_configuration.feature_configuration">feature_configuration</a>)
</pre>

Returns the C++ feature configuration nested inside the given Swift feature configuration.

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

A C++ `FeatureConfiguration` value (see `cc_common` for more information).

<a name="swift_common.compilation_attrs"></a>
## swift_common.compilation_attrs

<pre style="white-space: normal">
swift_common.compilation_attrs(<a href="#swift_common.compilation_attrs.additional_deps_aspects">additional_deps_aspects</a>=[])
</pre>

Returns an attribute dictionary for rules that compile Swift into objects.

The returned dictionary contains the subset of attributes that are shared by
the `swift_binary`, `swift_library`, and `swift_test` rules that deal with
inputs and options for compilation. Users who are authoring custom rules that
compile Swift code but not as a library can add this dictionary to their own
rule's attributes to give it a familiar API.

Do note, however, that it is the responsibility of the rule implementation to
retrieve the values of those attributes and pass them correctly to the other
`swift_common` APIs.

There is a hierarchy to the attribute sets offered by the `swift_common` API:

1. If you only need access to the toolchain for its tools and libraries but
   are not doing any compilation, use `toolchain_attrs`.
2. If you need to invoke compilation actions but are not making the resulting
   object files into a static or shared library, use `compilation_attrs`.
3. If you want to provide a rule interface that is suitable as a drop-in
   replacement for `swift_library`, use `library_rule_attrs`.

Each of the attribute functions in the list above also contains the attributes
from the earlier items in the list.

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
      <td><p><code>Optional; default is []</code></p><p>A list of additional aspects that should be applied
to <code>deps</code>. Defaults to the empty list. These must be passed by the
individual rules to avoid potential circular dependencies between the API
and the aspects; the API loaded the aspects directly, then those aspects
would not be able to load the API.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.compilation_attrs.returns"></a>
### Returns

A new attribute dictionary that can be added to the attributes of a custom
build rule to provide a similar interface to `swift_binary`,
`swift_library`, and `swift_test`.

<a name="swift_common.compile"></a>
## swift_common.compile

<pre style="white-space: normal">
swift_common.compile(<a href="#swift_common.compile.actions">actions</a>, <a href="#swift_common.compile.feature_configuration">feature_configuration</a>, <a href="#swift_common.compile.module_name">module_name</a>, <a href="#swift_common.compile.srcs">srcs</a>, <a href="#swift_common.compile.swift_toolchain">swift_toolchain</a>, <a href="#swift_common.compile.target_name">target_name</a>,
<a href="#swift_common.compile.additional_inputs">additional_inputs</a>=[], <a href="#swift_common.compile.bin_dir">bin_dir</a>=None, <a href="#swift_common.compile.copts">copts</a>=[], <a href="#swift_common.compile.defines">defines</a>=[], <a href="#swift_common.compile.deps">deps</a>=[], <a href="#swift_common.compile.genfiles_dir">genfiles_dir</a>=None)
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
      <td><p><code>Required</code></p><p>The name of the Swift module being compiled. This must be present and valid;
use <code>swift_common.derive_module_name</code> to generate a default from the target's label if
needed.</p></td>
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
      <td><p><code>Required</code></p><p>The name of the target for which the code is being compiled, which is used to
determine unique file paths for the outputs.</p></td>
    </tr>
    <tr id="swift_common.compile.additional_inputs">
      <td><code>additional_inputs</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>File</code>s representing additional input files that need to be
passed to the Swift compile action because they are referenced by compiler flags.</p></td>
    </tr>
    <tr id="swift_common.compile.bin_dir">
      <td><code>bin_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-bin</code> directory root. If provided, its path is used to store the cache
for modules precompiled by Swift's ClangImporter.</p></td>
    </tr>
    <tr id="swift_common.compile.copts">
      <td><code>copts</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of compiler flags that apply to the target being built. These flags, along
with those from Bazel's Swift configuration fragment (i.e., <code>--swiftcopt</code> command line
flags) are scanned to determine whether whole module optimization is being requested,
which affects the nature of the output files.</p></td>
    </tr>
    <tr id="swift_common.compile.defines">
      <td><code>defines</code></td>
      <td><p><code>Optional; default is []</code></p><p>Symbols that should be defined by passing <code>-D</code> to the compiler.</p></td>
    </tr>
    <tr id="swift_common.compile.deps">
      <td><code>deps</code></td>
      <td><p><code>Optional; default is []</code></p><p>Dependencies of the target being compiled. These targets must propagate one of the
following providers: <code>CcInfo</code>, <code>SwiftInfo</code>, or <code>apple_common.Objc</code>.</p></td>
    </tr>
    <tr id="swift_common.compile.genfiles_dir">
      <td><code>genfiles_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-genfiles</code> directory root. If provided, its path is added to
ClangImporter's header search paths for compatibility with Bazel's C++ and Objective-C
rules which support inclusions of generated headers from that location.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.compile.returns"></a>
### Returns

A `struct` containing the following fields:

*   `generated_header`: A `File` representing the Objective-C header that was generated for
    the compiled module. If no header was generated, this field will be None.
*   `generated_header_module_map`: A `File` representing the module map that was generated
    to correspond to the generated Objective-C header. If no module map was generated, this
    field will be None.
*   `indexstore`: A `File` representing the directory that contains the index store data
    generated by the compiler if index-while-building is enabled. May be None if no
    indexing was requested.
*   `linker_flags`: A list of strings representing additional flags that should be passed
    to the linker when linking these objects into a binary. If there are none, this field
    will always be an empty list, never None.
*   `linker_inputs`: A list of `File`s representing additional input files (such as those
    referenced in `linker_flags`) that need to be available to the link action when linking
    these objects into a binary. If there are none, this field will always be an empty
    list, never None.
*   `object_files`: A list of `.o` files that were produced by the compiler.
*   `stats_directory`: A `File` representing the directory that contains the timing
    statistics emitted by the compiler. If no stats were requested, this field will be
    None.
*   `swiftdoc`: The `.swiftdoc` file that was produced by the compiler.
*   `swiftmodule`: The `.swiftmodule` file that was produced by the compiler.

<a name="swift_common.configure_features"></a>
## swift_common.configure_features

<pre style="white-space: normal">
swift_common.configure_features(<a href="#swift_common.configure_features.ctx">ctx</a>, <a href="#swift_common.configure_features.swift_toolchain">swift_toolchain</a>, <a href="#swift_common.configure_features.requested_features">requested_features</a>=[], <a href="#swift_common.configure_features.unsupported_features">unsupported_features</a>=[])
</pre>

Creates a feature configuration that should be passed to other Swift build APIs.

This function calls through to `cc_common.configure_features` to configure underlying C++
features as well, and nests the C++ feature configuration inside the Swift one. Users who need
to call C++ APIs that require a feature configuration can extract it by calling
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
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain being used to build.
The C++ toolchain associated with the Swift toolchain is used to create the underlying
C++ feature configuration.</p></td>
    </tr>
    <tr id="swift_common.configure_features.requested_features">
      <td><code>requested_features</code></td>
      <td><p><code>Optional; default is []</code></p><p>The list of features to be enabled. This is typically obtained using
the <code>ctx.features</code> field in a rule implementation function.</p></td>
    </tr>
    <tr id="swift_common.configure_features.unsupported_features">
      <td><code>unsupported_features</code></td>
      <td><p><code>Optional; default is []</code></p><p>The list of features that are unsupported by the current rule. This
is typically obtained using the <code>ctx.disabled_features</code> field in a rule implementation
function.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.configure_features.returns"></a>
### Returns

An opaque value representing the feature configuration that can be passed to other
`swift_common` functions.

<a name="swift_common.create_swift_info"></a>
## swift_common.create_swift_info

<pre style="white-space: normal">
swift_common.create_swift_info(<a href="#swift_common.create_swift_info.defines">defines</a>=[], <a href="#swift_common.create_swift_info.modulemaps">modulemaps</a>=[], <a href="#swift_common.create_swift_info.module_name">module_name</a>=None, <a href="#swift_common.create_swift_info.swiftdocs">swiftdocs</a>=[],
<a href="#swift_common.create_swift_info.swiftmodules">swiftmodules</a>=[], <a href="#swift_common.create_swift_info.swift_infos">swift_infos</a>=[], <a href="#swift_common.create_swift_info.swift_version">swift_version</a>=None)
</pre>

Creates a new `SwiftInfo` provider with the given values.

This function is recommended instead of directly creating a `SwiftInfo` provider because it
encodes reasonable defaults for fields that some rules may not be interested in and ensures
that the direct and transitive fields are set consistently.

This function can also be used to do a simple merge of `SwiftInfo` providers, by leaving all
of the arguments except for `swift_infos` as their empty defaults. In that case, the returned
provider will not represent a true Swift module; it is merely a "collector" for other
dependencies.

<a name="swift_common.create_swift_info.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.create_swift_info.defines">
      <td><code>defines</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of defines that will be provided as <code>copts</code> of the target being built.</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.modulemaps">
      <td><code>modulemaps</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of module maps that should be passed to ClangImporter by any target
that depends on the one propagating this provider.</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.module_name">
      <td><code>module_name</code></td>
      <td><p><code>Optional; default is None</code></p><p>A string containing the name of the Swift module. If this is <code>None</code>, the
provider does not represent a compiled module but rather a collection of modules (this
happens, for example, with <code>proto_library</code> targets that have no sources of their own
but depend on others that do).</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.swiftdocs">
      <td><code>swiftdocs</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>.swiftdoc</code> files that are the direct outputs of the target being
built. If omitted, an empty list is used.</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.swiftmodules">
      <td><code>swiftmodules</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>.swiftmodule</code> files that are the direct outputs of the target
being built. If omitted, an empty list is used.</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.swift_infos">
      <td><code>swift_infos</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>SwiftInfo</code> providers from dependencies, whose transitive fields
should be merged into the new one. If omitted, no transitive data is collected.</p></td>
    </tr>
    <tr id="swift_common.create_swift_info.swift_version">
      <td><code>swift_version</code></td>
      <td><p><code>Optional; default is None</code></p><p>A string containing the value of the <code>-swift-version</code> flag used when
compiling this target, or <code>None</code> (the default) if it was not set or is not relevant.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.create_swift_info.returns"></a>
### Returns

A new `SwiftInfo` provider with the given values.

<a name="swift_common.derive_module_name"></a>
## swift_common.derive_module_name

<pre style="white-space: normal">
swift_common.derive_module_name(<a href="#swift_common.derive_module_name.*args">*args</a>)
</pre>

Returns a derived module name from the given build label.

For targets whose module name is not explicitly specified, the module name is
computed by creating an underscore-delimited string from the components of the
label, replacing any non-identifier characters also with underscores.

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
      <td><p>Either a single argument of type <code>Label</code>, or two arguments of type
<code>str</code> where the first argument is the package name and the second
argument is the target name.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.derive_module_name.returns"></a>
### Returns

The module name derived from the label.

<a name="swift_common.is_enabled"></a>
## swift_common.is_enabled

<pre style="white-space: normal">
swift_common.is_enabled(<a href="#swift_common.is_enabled.feature_configuration">feature_configuration</a>, <a href="#swift_common.is_enabled.feature_name">feature_name</a>)
</pre>

Returns `True` if the given feature is enabled in the feature configuration.

This function handles both Swift-specific features and C++ features so that users do not have
to manually extract the C++ configuration in order to check it.

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
specifies the toolchain dependency). Users who are authoring custom rules can
use this dictionary verbatim or add other custom attributes to it in order to
make their rule a drop-in replacement for `swift_library` (for example, if
writing a custom rule that does some preprocessing or generation of sources
and then compiles them).

Do note, however, that it is the responsibility of the rule implementation to
retrieve the values of those attributes and pass them correctly to the other
`swift_common` APIs.

There is a hierarchy to the attribute sets offered by the `swift_common` API:

1. If you only need access to the toolchain for its tools and libraries but
   are not doing any compilation, use `toolchain_attrs`.
2. If you need to invoke compilation actions but are not making the resulting
   object files into a static or shared library, use `compilation_attrs`.
3. If you want to provide a rule interface that is suitable as a drop-in
   replacement for `swift_library`, use `library_rule_attrs`.

Each of the attribute functions in the list above also contains the attributes
from the earlier items in the list.

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
      <td><p><code>Optional; default is []</code></p><p>A list of additional aspects that should be applied
to <code>deps</code>. Defaults to the empty list. These must be passed by the
individual rules to avoid potential circular dependencies between the API
and the aspects; the API loaded the aspects directly, then those aspects
would not be able to load the API.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.library_rule_attrs.returns"></a>
### Returns

A new attribute dictionary that can be added to the attributes of a custom
build rule to provide the same interface as `swift_library`.

<a name="swift_common.swift_runtime_linkopts"></a>
## swift_common.swift_runtime_linkopts

<pre style="white-space: normal">
swift_common.swift_runtime_linkopts(<a href="#swift_common.swift_runtime_linkopts.is_static">is_static</a>, <a href="#swift_common.swift_runtime_linkopts.toolchain">toolchain</a>, <a href="#swift_common.swift_runtime_linkopts.is_test">is_test</a>=False)
</pre>

Returns the flags that should be passed to `clang` when linking a binary.

This function provides the appropriate linker arguments to callers who need to
link a binary using something other than `swift_binary` (for example, an
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
      <td><p><code>Required</code></p><p>A <code>Boolean</code> value indicating whether the binary should be linked
against the static (rather than the dynamic) Swift runtime libraries.</p></td>
    </tr>
    <tr id="swift_common.swift_runtime_linkopts.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain whose linker
options are desired.</p></td>
    </tr>
    <tr id="swift_common.swift_runtime_linkopts.is_test">
      <td><code>is_test</code></td>
      <td><p><code>Optional; default is False</code></p><p>A <code>Boolean</code> value indicating whether the target being linked is a
test target.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.swift_runtime_linkopts.returns"></a>
### Returns

A `list` of command-line flags that should be passed to `clang` to link
against the Swift runtime libraries.

<a name="swift_common.swiftc_command_line_and_inputs"></a>
## swift_common.swiftc_command_line_and_inputs

<pre style="white-space: normal">
swift_common.swiftc_command_line_and_inputs(<a href="#swift_common.swiftc_command_line_and_inputs.args">args</a>, <a href="#swift_common.swiftc_command_line_and_inputs.feature_configuration">feature_configuration</a>, <a href="#swift_common.swiftc_command_line_and_inputs.module_name">module_name</a>, <a href="#swift_common.swiftc_command_line_and_inputs.srcs">srcs</a>,
<a href="#swift_common.swiftc_command_line_and_inputs.toolchain">toolchain</a>, <a href="#swift_common.swiftc_command_line_and_inputs.additional_input_depsets">additional_input_depsets</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.copts">copts</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.defines">defines</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.deps">deps</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.genfiles_dir">genfiles_dir</a>=None)
</pre>

Computes command line arguments and inputs needed to invoke `swiftc`.

The command line arguments computed by this function are any that do *not*
require the declaration of new output files. For example, it includes the list
of frameworks, defines, source files, and other copts, but not flags like the
output objects or `.swiftmodule` files. The purpose of this is to allow
(nearly) the same command line that would be passed to the compiler to be
passed to other tools that require it; the most common application of this is
for tools that use SourceKit, which need to know the command line in order to
gather information about dependencies for indexing and code completion.

<a name="swift_common.swiftc_command_line_and_inputs.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.swiftc_command_line_and_inputs.args">
      <td><code>args</code></td>
      <td><p><code>Required</code></p><p>An <code>Args</code> object into which the command line arguments will be added.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Required</code></p><p>A feature configuration obtained from
<code>swift_common.configure_features</code>.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.module_name">
      <td><code>module_name</code></td>
      <td><p><code>Required</code></p><p>The name of the Swift module being compiled. This must be
present and valid; use <code>swift_common.derive_module_name</code> to generate a
default from the target's label if needed.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.srcs">
      <td><code>srcs</code></td>
      <td><p><code>Required</code></p><p>The Swift source files to compile.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.additional_input_depsets">
      <td><code>additional_input_depsets</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>depset</code>s of <code>File</code>s representing
additional input files that need to be passed to the Swift compile
action because they are referenced by compiler flags.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.copts">
      <td><code>copts</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list (<strong>not</strong> an <code>Args</code> object) of compiler flags that apply to the
target being built. These flags, along with those from Bazel's Swift
configuration fragment (i.e., <code>--swiftcopt</code> command line flags) are
scanned to determine whether whole module optimization is being
requested, which affects the nature of the output files.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.defines">
      <td><code>defines</code></td>
      <td><p><code>Optional; default is []</code></p><p>Symbols that should be defined by passing <code>-D</code> to the compiler.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.deps">
      <td><code>deps</code></td>
      <td><p><code>Optional; default is []</code></p><p>Dependencies of the target being compiled. These targets must
propagate one of the following providers: <code>CcInfo</code>, <code>SwiftInfo</code>, or
<code>apple_common.Objc</code>.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.genfiles_dir">
      <td><code>genfiles_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-genfiles</code> directory root. If provided, its path
is added to ClangImporter's header search paths for compatibility with
Bazel's C++ and Objective-C rules which support inclusions of generated
headers from that location.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.swiftc_command_line_and_inputs.returns"></a>
### Returns

A `depset` containing the full set of files that need to be passed as inputs
of the Bazel action that spawns a tool with the computed command line (i.e.,
any source files, referenced module maps and headers, and so forth.)

<a name="swift_common.toolchain_attrs"></a>
## swift_common.toolchain_attrs

<pre style="white-space: normal">
swift_common.toolchain_attrs(<a href="#swift_common.toolchain_attrs.toolchain_attr_name">toolchain_attr_name</a>=_toolchain)
</pre>

Returns an attribute dictionary for toolchain users.

The returned dictionary contains a key with the name specified by the
argument `toolchain_attr_name` (which defaults to the value `"_toolchain"`),
the value of which is a BUILD API `attr.label` that references the default
Swift toolchain. Users who are authoring custom rules can add this dictionary
to the attributes of their own rule in order to depend on the toolchain and
access its `SwiftToolchainInfo` provider to pass it to other `swift_common`
functions.

There is a hierarchy to the attribute sets offered by the `swift_common` API:

1. If you only need access to the toolchain for its tools and libraries but
   are not doing any compilation, use `toolchain_attrs`.
2. If you need to invoke compilation actions but are not making the resulting
   object files into a static or shared library, use `compilation_attrs`.
3. If you want to provide a rule interface that is suitable as a drop-in
   replacement for `swift_library`, use `library_rule_attrs`.

Each of the attribute functions in the list above also contains the attributes
from the earlier items in the list.

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
      <td><p><code>Optional; default is _toolchain</code></p><p>The name of the attribute that should be created that
points to the toolchain. This defaults to <code>_toolchain</code>, which is
sufficient for most rules; it is customizable for certain aspects where
having an attribute with the same name but different values applied to
a particular target causes a build crash.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.toolchain_attrs.returns"></a>
### Returns

A new attribute dictionary that can be added to the attributes of a custom
build rule to provide access to the Swift toolchain.



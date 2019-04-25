# Build API


The `swift_common` module provides API access to the behavior implemented
by the Swift build rules, so that other custom rules can invoke Swift
compilation and/or linking as part of their implementation.

On this page:

  * [swift_common.build_swift_info](#swift_common.build_swift_info)
  * [swift_common.compilation_attrs](#swift_common.compilation_attrs)
  * [swift_common.compilation_mode_copts](#swift_common.compilation_mode_copts)
  * [swift_common.compile_as_library](#swift_common.compile_as_library)
  * [swift_common.compile_as_objects](#swift_common.compile_as_objects)
  * [swift_common.configure_features](#swift_common.configure_features)
  * [swift_common.derive_module_name](#swift_common.derive_module_name)
  * [swift_common.get_disabled_features](#swift_common.get_disabled_features)
  * [swift_common.get_enabled_features](#swift_common.get_enabled_features)
  * [swift_common.library_rule_attrs](#swift_common.library_rule_attrs)
  * [swift_common.merge_swift_info_providers](#swift_common.merge_swift_info_providers)
  * [swift_common.run_toolchain_action](#swift_common.run_toolchain_action)
  * [swift_common.run_toolchain_shell_action](#swift_common.run_toolchain_shell_action)
  * [swift_common.run_toolchain_swift_action](#swift_common.run_toolchain_swift_action)
  * [swift_common.swift_runtime_linkopts](#swift_common.swift_runtime_linkopts)
  * [swift_common.swiftc_command_line_and_inputs](#swift_common.swiftc_command_line_and_inputs)
  * [swift_common.toolchain_attrs](#swift_common.toolchain_attrs)

<a name="swift_common.build_swift_info"></a>
## swift_common.build_swift_info

<pre style="white-space: normal">
swift_common.build_swift_info(<a href="#swift_common.build_swift_info.additional_cc_libs">additional_cc_libs</a>=[], <a href="#swift_common.build_swift_info.compile_options">compile_options</a>=[], <a href="#swift_common.build_swift_info.deps">deps</a>=[],
<a href="#swift_common.build_swift_info.direct_additional_inputs">direct_additional_inputs</a>=[], <a href="#swift_common.build_swift_info.direct_defines">direct_defines</a>=[], <a href="#swift_common.build_swift_info.direct_libraries">direct_libraries</a>=[], <a href="#swift_common.build_swift_info.direct_linkopts">direct_linkopts</a>=[],
<a href="#swift_common.build_swift_info.direct_swiftdocs">direct_swiftdocs</a>=[], <a href="#swift_common.build_swift_info.direct_swiftmodules">direct_swiftmodules</a>=[], <a href="#swift_common.build_swift_info.module_name">module_name</a>=None, <a href="#swift_common.build_swift_info.swift_version">swift_version</a>=None)
</pre>

Builds a `SwiftInfo` provider from direct outputs and dependencies.

This function is recommended instead of directly creating a `SwiftInfo` provider because it
encodes reasonable defaults for fields that some rules may not be interested in, and because it
also automatically collects transitive values from dependencies.

<a name="swift_common.build_swift_info.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.build_swift_info.additional_cc_libs">
      <td><code>additional_cc_libs</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of additional <code>cc_library</code> dependencies whose libraries and
linkopts need to be propagated by <code>SwiftInfo</code>.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.compile_options">
      <td><code>compile_options</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>Args</code> objects that contain the compilation options passed to
<code>swiftc</code> to compile this target.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.deps">
      <td><code>deps</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of dependencies of the target being built, which provide <code>SwiftInfo</code> providers.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.direct_additional_inputs">
      <td><code>direct_additional_inputs</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of additional input files passed into a library or binary
target via the <code>swiftc_inputs</code> attribute.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.direct_defines">
      <td><code>direct_defines</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of defines that will be provided as <code>copts</code> of the target being
built.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.direct_libraries">
      <td><code>direct_libraries</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>.a</code> files that are the direct outputs of the target being
built.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.direct_linkopts">
      <td><code>direct_linkopts</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of linker flags that will be passed to the linker when the target
being built is linked into a binary.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.direct_swiftdocs">
      <td><code>direct_swiftdocs</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>.swiftdoc</code> files that are the direct outputs of the target
being built.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.direct_swiftmodules">
      <td><code>direct_swiftmodules</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>.swiftmodule</code> files that are the direct outputs of the
target being built.</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.module_name">
      <td><code>module_name</code></td>
      <td><p><code>Optional; default is None</code></p><p>A string containing the name of the Swift module, or <code>None</code> if the provider
does not represent a compiled module (this happens, for example, with <code>proto_library</code>
targets that act as "collectors" of other modules but have no sources of their own).</p></td>
    </tr>
    <tr id="swift_common.build_swift_info.swift_version">
      <td><code>swift_version</code></td>
      <td><p><code>Optional; default is None</code></p><p>A string containing the value of the <code>-swift-version</code> flag used when
compiling this target, or <code>None</code> if it was not set or is not relevant.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.build_swift_info.returns"></a>
### Returns

A new `SwiftInfo` provider that propagates the direct and transitive libraries and modules
for the target being built.

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

<a name="swift_common.compilation_mode_copts"></a>
## swift_common.compilation_mode_copts

<pre style="white-space: normal">
swift_common.compilation_mode_copts(<a href="#swift_common.compilation_mode_copts.allow_testing">allow_testing</a>, <a href="#swift_common.compilation_mode_copts.compilation_mode">compilation_mode</a>, <a href="#swift_common.compilation_mode_copts.wants_dsyms">wants_dsyms</a>=False)
</pre>

Returns `swiftc` compilation flags that match the given compilation mode.

<a name="swift_common.compilation_mode_copts.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.compilation_mode_copts.allow_testing">
      <td><code>allow_testing</code></td>
      <td><p><code>Required</code></p><p>If <code>True</code>, the <code>-enable-testing</code> flag will also be added to
"dbg" and "fastbuild" builds. This argument is ignored for "opt" builds.</p></td>
    </tr>
    <tr id="swift_common.compilation_mode_copts.compilation_mode">
      <td><code>compilation_mode</code></td>
      <td><p><code>Required</code></p><p>The compilation mode string ("fastbuild", "dbg", or
"opt"). The build will fail if this is <code>None</code> or some other unrecognized
mode.</p></td>
    </tr>
    <tr id="swift_common.compilation_mode_copts.wants_dsyms">
      <td><code>wants_dsyms</code></td>
      <td><p><code>Optional; default is False</code></p><p>If <code>True</code>, the caller is requesting that the debug information
be extracted into dSYM binaries. This affects the debug mode used during
compilation.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.compilation_mode_copts.returns"></a>
### Returns

A list of strings containing copts that should be passed to Swift.

<a name="swift_common.compile_as_library"></a>
## swift_common.compile_as_library

<pre style="white-space: normal">
swift_common.compile_as_library(<a href="#swift_common.compile_as_library.actions">actions</a>, <a href="#swift_common.compile_as_library.bin_dir">bin_dir</a>, <a href="#swift_common.compile_as_library.compilation_mode">compilation_mode</a>, <a href="#swift_common.compile_as_library.label">label</a>, <a href="#swift_common.compile_as_library.module_name">module_name</a>, <a href="#swift_common.compile_as_library.srcs">srcs</a>,
<a href="#swift_common.compile_as_library.swift_fragment">swift_fragment</a>, <a href="#swift_common.compile_as_library.toolchain">toolchain</a>, <a href="#swift_common.compile_as_library.additional_inputs">additional_inputs</a>=[], <a href="#swift_common.compile_as_library.allow_testing">allow_testing</a>=True, <a href="#swift_common.compile_as_library.alwayslink">alwayslink</a>=False, <a href="#swift_common.compile_as_library.cc_libs">cc_libs</a>=[],
<a href="#swift_common.compile_as_library.configuration">configuration</a>=None, <a href="#swift_common.compile_as_library.copts">copts</a>=[], <a href="#swift_common.compile_as_library.defines">defines</a>=[], <a href="#swift_common.compile_as_library.deps">deps</a>=[], <a href="#swift_common.compile_as_library.feature_configuration">feature_configuration</a>=None, <a href="#swift_common.compile_as_library.genfiles_dir">genfiles_dir</a>=None,
<a href="#swift_common.compile_as_library.library_name">library_name</a>=None, <a href="#swift_common.compile_as_library.linkopts">linkopts</a>=[], <a href="#swift_common.compile_as_library.objc_fragment">objc_fragment</a>=None)
</pre>

Compiles Swift source files into static and/or shared libraries.

This is a high-level API that wraps the compilation and library creation steps
based on the provided input arguments, and is likely suitable for most common
purposes.

If the toolchain supports Objective-C interop, then this function also
generates an Objective-C header file for the library and returns an `Objc`
provider that allows other `objc_library` targets to depend on it.

<a name="swift_common.compile_as_library.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.compile_as_library.actions">
      <td><code>actions</code></td>
      <td><p><code>Required</code></p><p>The rule context's <code>actions</code> object.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.bin_dir">
      <td><code>bin_dir</code></td>
      <td><p><code>Required</code></p><p>The Bazel <code>*-bin</code> directory root.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.compilation_mode">
      <td><code>compilation_mode</code></td>
      <td><p><code>Required</code></p><p>The Bazel compilation mode; must be <code>dbg</code>, <code>fastbuild</code>, or
<code>opt</code>.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.label">
      <td><code>label</code></td>
      <td><p><code>Required</code></p><p>The target label for which the code is being compiled, which is used
to determine unique file paths for the outputs.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.module_name">
      <td><code>module_name</code></td>
      <td><p><code>Required</code></p><p>The name of the Swift module being compiled. This must be
present and valid; use <code>swift_common.derive_module_name</code> to generate a
default from the target's label if needed.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.srcs">
      <td><code>srcs</code></td>
      <td><p><code>Required</code></p><p>The Swift source files to compile.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.swift_fragment">
      <td><code>swift_fragment</code></td>
      <td><p><code>Required</code></p><p>The <code>swift</code> configuration fragment from Bazel.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.additional_inputs">
      <td><code>additional_inputs</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>File</code>s representing additional inputs that
need to be passed to the Swift compile action because they are
referenced in compiler flags.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.allow_testing">
      <td><code>allow_testing</code></td>
      <td><p><code>Optional; default is True</code></p><p>Indicates whether the module should be compiled with testing
enabled (only when the compilation mode is <code>fastbuild</code> or <code>dbg</code>).</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.alwayslink">
      <td><code>alwayslink</code></td>
      <td><p><code>Optional; default is False</code></p><p>Indicates whether the object files in the library should always
be always be linked into any binaries that depend on it, even if some
contain no symbols referenced by the binary.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.cc_libs">
      <td><code>cc_libs</code></td>
      <td><p><code>Optional; default is []</code></p><p>Additional <code>cc_library</code> targets whose static libraries should be
merged into the resulting archive.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.configuration">
      <td><code>configuration</code></td>
      <td><p><code>Optional; default is None</code></p><p>The default configuration from which certain compilation
options are determined, such as whether coverage is enabled. This object
should be one obtained from a rule's <code>ctx.configuraton</code> field. If
omitted, no default-configuration-specific options will be used.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.copts">
      <td><code>copts</code></td>
      <td><p><code>Optional; default is []</code></p><p>Additional flags that should be passed to <code>swiftc</code>.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.defines">
      <td><code>defines</code></td>
      <td><p><code>Optional; default is []</code></p><p>Symbols that should be defined by passing <code>-D</code> to the compiler.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.deps">
      <td><code>deps</code></td>
      <td><p><code>Optional; default is []</code></p><p>Dependencies of the target being compiled. These targets must
propagate one of the following providers: <code>SwiftClangModuleInfo</code>,
<code>SwiftInfo</code>, <code>"cc"</code>, or <code>apple_common.Objc</code>.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Optional; default is None</code></p><p>A feature configuration obtained from
<code>swift_common.configure_features</code>. If omitted, a default feature
configuration will be used, but this argument will be required in the
future.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.genfiles_dir">
      <td><code>genfiles_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-genfiles</code> directory root. If provided, its path
is added to ClangImporter's header search paths for compatibility with
Bazel's C++ and Objective-C rules which support inclusions of generated
headers from that location.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.library_name">
      <td><code>library_name</code></td>
      <td><p><code>Optional; default is None</code></p><p>The name that should be substituted for the string <code>{name}</code> in
<code>lib{name}.a</code>, which will be the output of this compilation. If this is
not specified or is falsy, then the default behavior is to simply use
the name of the build target.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.linkopts">
      <td><code>linkopts</code></td>
      <td><p><code>Optional; default is []</code></p><p>Additional flags that should be passed to the linker when the
target being compiled is linked into a binary. These options are not
used directly by any action registered by this function, but they are
added to the <code>SwiftInfo</code> provider that it returns so that the linker
flags can be propagated to dependent targets.</p></td>
    </tr>
    <tr id="swift_common.compile_as_library.objc_fragment">
      <td><code>objc_fragment</code></td>
      <td><p><code>Optional; default is None</code></p><p>The <code>objc</code> configuration fragment from Bazel. This must be
provided if the toolchain supports Objective-C interop; if it does not,
then this argument may be omitted.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.compile_as_library.returns"></a>
### Returns

A `struct` containing the following fields:

* `compile_inputs`: A `depset` of `File`s representing the full collection
  of files that were used as inputs to the compile action. This can be used
  if those files need to also be made available to subsequent link actions.
* `compile_options`: A list of `Args` objects containing the complete set
  of command line flags that were passed to the compiler. This is mainly
  exposed for aspects to inspect so that IDEs can integrate with SourceKit.
* `output_archive`: The static archive (`.a`) that was produced by the
  archiving step after compilation.
* `output_doc`: The `.swiftdoc` file that was produced by the compiler.
* `output_groups`: A dictionary of output groups that should be returned by
  the calling rule through the `OutputGroupInfo` provider.
* `output_module`: The `.swiftmodule` file that was produced by the
  compiler.
* `providers`: A list of providers that should be returned by the calling
  rule. This includes the `SwiftInfo` provider, and if Objective-C interop
  is enabled on the toolchain, an `apple_common.Objc` provider as well.

<a name="swift_common.compile_as_objects"></a>
## swift_common.compile_as_objects

<pre style="white-space: normal">
swift_common.compile_as_objects(<a href="#swift_common.compile_as_objects.actions">actions</a>, <a href="#swift_common.compile_as_objects.arguments">arguments</a>, <a href="#swift_common.compile_as_objects.compilation_mode">compilation_mode</a>, <a href="#swift_common.compile_as_objects.module_name">module_name</a>, <a href="#swift_common.compile_as_objects.srcs">srcs</a>,
<a href="#swift_common.compile_as_objects.swift_fragment">swift_fragment</a>, <a href="#swift_common.compile_as_objects.target_name">target_name</a>, <a href="#swift_common.compile_as_objects.toolchain">toolchain</a>, <a href="#swift_common.compile_as_objects.additional_input_depsets">additional_input_depsets</a>=[], <a href="#swift_common.compile_as_objects.additional_outputs">additional_outputs</a>=[],
<a href="#swift_common.compile_as_objects.allow_testing">allow_testing</a>=True, <a href="#swift_common.compile_as_objects.configuration">configuration</a>=None, <a href="#swift_common.compile_as_objects.copts">copts</a>=[], <a href="#swift_common.compile_as_objects.defines">defines</a>=[], <a href="#swift_common.compile_as_objects.deps">deps</a>=[], <a href="#swift_common.compile_as_objects.feature_configuration">feature_configuration</a>=None,
<a href="#swift_common.compile_as_objects.genfiles_dir">genfiles_dir</a>=None, <a href="#swift_common.compile_as_objects.objc_fragment">objc_fragment</a>=None)
</pre>

Compiles Swift source files into object files (and optionally a module).

<a name="swift_common.compile_as_objects.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.compile_as_objects.actions">
      <td><code>actions</code></td>
      <td><p><code>Required</code></p><p>The context's <code>actions</code> object.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.arguments">
      <td><code>arguments</code></td>
      <td><p><code>Required</code></p><p>A list of <code>Args</code> objects that provide additional arguments to the
compiler, not including the <code>copts</code> list.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.compilation_mode">
      <td><code>compilation_mode</code></td>
      <td><p><code>Required</code></p><p>The Bazel compilation mode; must be <code>dbg</code>, <code>fastbuild</code>, or
<code>opt</code>.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.module_name">
      <td><code>module_name</code></td>
      <td><p><code>Required</code></p><p>The name of the Swift module being compiled. This must be
present and valid; use <code>swift_common.derive_module_name</code> to generate a
default from the target's label if needed.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.srcs">
      <td><code>srcs</code></td>
      <td><p><code>Required</code></p><p>The Swift source files to compile.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.swift_fragment">
      <td><code>swift_fragment</code></td>
      <td><p><code>Required</code></p><p>The <code>swift</code> configuration fragment from Bazel.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.target_name">
      <td><code>target_name</code></td>
      <td><p><code>Required</code></p><p>The name of the target for which the code is being compiled,
which is used to determine unique file paths for the outputs.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.additional_input_depsets">
      <td><code>additional_input_depsets</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>depset</code>s of <code>File</code>s representing
additional input files that need to be passed to the Swift compile
action because they are referenced by compiler flags.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.additional_outputs">
      <td><code>additional_outputs</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list of <code>File</code>s representing files that should be
treated as additional outputs of the compilation action.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.allow_testing">
      <td><code>allow_testing</code></td>
      <td><p><code>Optional; default is True</code></p><p>Indicates whether the module should be compiled with testing
enabled (only when the compilation mode is <code>fastbuild</code> or <code>dbg</code>).</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.configuration">
      <td><code>configuration</code></td>
      <td><p><code>Optional; default is None</code></p><p>The default configuration from which certain compilation
options are determined, such as whether coverage is enabled. This object
should be one obtained from a rule's <code>ctx.configuraton</code> field. If
omitted, no default-configuration-specific options will be used.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.copts">
      <td><code>copts</code></td>
      <td><p><code>Optional; default is []</code></p><p>A list (<strong>not</strong> an <code>Args</code> object) of compiler flags that apply to the
target being built. These flags, along with those from Bazel's Swift
configuration fragment (i.e., <code>--swiftcopt</code> command line flags) are
scanned to determine whether whole module optimization is being
requested, which affects the nature of the output files.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.defines">
      <td><code>defines</code></td>
      <td><p><code>Optional; default is []</code></p><p>Symbols that should be defined by passing <code>-D</code> to the compiler.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.deps">
      <td><code>deps</code></td>
      <td><p><code>Optional; default is []</code></p><p>Dependencies of the target being compiled. These targets must
propagate one of the following providers: <code>SwiftClangModuleInfo</code>,
<code>SwiftInfo</code>, <code>"cc"</code>, or <code>apple_common.Objc</code>.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Optional; default is None</code></p><p>A feature configuration obtained from
<code>swift_common.configure_features</code>. If omitted, a default feature
configuration will be used, but this argument will be required in the
future.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.genfiles_dir">
      <td><code>genfiles_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-genfiles</code> directory root. If provided, its path
is added to ClangImporter's header search paths for compatibility with
Bazel's C++ and Objective-C rules which support inclusions of generated
headers from that location.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.objc_fragment">
      <td><code>objc_fragment</code></td>
      <td><p><code>Optional; default is None</code></p><p>The <code>objc</code> configuration fragment from Bazel. This must be
provided if the toolchain supports Objective-C interop; if it does not,
then this argument may be omitted.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.compile_as_objects.returns"></a>
### Returns

A `struct` containing the following fields:

* `compile_inputs`: A `depset` of `File`s representing the full collection
  of files that were used as inputs to the compile action. This can be used
  if those files need to also be made available to subsequent link actions.
* `compile_options`: A list of `Args` objects containing the complete set
  of command line flags that were passed to the compiler. This is mainly
  exposed for aspects to inspect so that IDEs can integrate with SourceKit.
* `linker_flags`: A list of strings representing additional flags that
  should be passed to the linker when linking these objects into a binary.
* `linker_inputs`: A list of `File`s representing additional input files
  (such as those referenced in `linker_flags`) that need to be available to
  the linker action when linking these objects into a binary.
* `output_doc`: The `.swiftdoc` file that was produced by the compiler.
* `output_groups`: A dictionary of output groups that should be returned by
  the calling rule through the `OutputGroupInfo` provider.
* `output_module`: The `.swiftmodule` file that was produced by the
  compiler.
* `output_objects`: The object (`.o`) files that were produced by the
  compiler.

<a name="swift_common.configure_features"></a>
## swift_common.configure_features

<pre style="white-space: normal">
swift_common.configure_features(<a href="#swift_common.configure_features.toolchain">toolchain</a>, <a href="#swift_common.configure_features.requested_features">requested_features</a>=[], <a href="#swift_common.configure_features.unsupported_features">unsupported_features</a>=[])
</pre>

Creates a feature configuration that should be passed to other Swift build APIs.

The feature configuration is a value that encapsulates the list of features that have been
explicitly enabled or disabled by the user as well as those enabled or disabled by the
toolchain. The other Swift build APIs query this value to determine which features should be
used during the build.

Users should treat the return value of this function as an opaque value and should only operate
on it using other API functions, like `swift_common.get_{enabled,disabled}_features`. Its
internal representation is an implementation detail and subject to change.

<a name="swift_common.configure_features.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.configure_features.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider of the toolchain being used to build.</p></td>
    </tr>
    <tr id="swift_common.configure_features.requested_features">
      <td><code>requested_features</code></td>
      <td><p><code>Optional; default is []</code></p><p>The list of user-enabled features <em>only</em>. This is typically obtained
using the <code>ctx.features</code> field in a rule implementation function. It should <em>not</em> be
merged with any features from the toolchain; the feature configuration manages those.</p></td>
    </tr>
    <tr id="swift_common.configure_features.unsupported_features">
      <td><code>unsupported_features</code></td>
      <td><p><code>Optional; default is []</code></p><p>The list of user-disabled features <em>only</em>. This is typically obtained
using the <code>ctx.disabled_features</code> field in a rule implementation function. It should
<em>not</em> be merged with any disabled features from the toolchain; the feature configuration
manages those.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.configure_features.returns"></a>
### Returns

An opaque value that should be passed as the `feature_configuration` argument of other
`swift_common` API calls.

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

<a name="swift_common.get_disabled_features"></a>
## swift_common.get_disabled_features

<pre style="white-space: normal">
swift_common.get_disabled_features(<a href="#swift_common.get_disabled_features.feature_configuration">feature_configuration</a>)
</pre>

Returns the list of disabled features in the feature configuration.

<a name="swift_common.get_disabled_features.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.get_disabled_features.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Required</code></p><p>The feature configuration.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.get_disabled_features.returns"></a>
### Returns

A list containing the names of features that are disabled in the given feature
configuration.

<a name="swift_common.get_enabled_features"></a>
## swift_common.get_enabled_features

<pre style="white-space: normal">
swift_common.get_enabled_features(<a href="#swift_common.get_enabled_features.feature_configuration">feature_configuration</a>)
</pre>

Returns the list of enabled features in the feature configuration.

<a name="swift_common.get_enabled_features.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.get_enabled_features.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Required</code></p><p>The feature configuration.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.get_enabled_features.returns"></a>
### Returns

A list containing the names of features that are enabled in the given feature configuration.

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

<a name="swift_common.merge_swift_info_providers"></a>
## swift_common.merge_swift_info_providers

<pre style="white-space: normal">
swift_common.merge_swift_info_providers(<a href="#swift_common.merge_swift_info_providers.targets">targets</a>)
</pre>

Merges the transitive `SwiftInfo` of the given targets into a new provider.

This function should be used when it is necessary to merge `SwiftInfo`
providers outside of a compile action (which does it automatically).

<a name="swift_common.merge_swift_info_providers.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.merge_swift_info_providers.targets">
      <td><code>targets</code></td>
      <td><p><code>Required</code></p><p>A sequence of targets that may propagate <code>SwiftInfo</code> providers.
Those that do not are ignored.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.merge_swift_info_providers.returns"></a>
### Returns

A new `SwiftInfo` provider that contains the transitive information from all
the targets.

<a name="swift_common.run_toolchain_action"></a>
## swift_common.run_toolchain_action

<pre style="white-space: normal">
swift_common.run_toolchain_action(<a href="#swift_common.run_toolchain_action.actions">actions</a>, <a href="#swift_common.run_toolchain_action.toolchain">toolchain</a>, <a href="#swift_common.run_toolchain_action.**kwargs">**kwargs</a>)
</pre>

Equivalent to `actions.run`, but respecting toolchain settings.

This function applies the toolchain's environment and execution requirements and also wraps the
command in a wrapper executable if the toolchain requires it (for example, `xcrun` on Darwin).

If the `executable` argument is a simple basename and the toolchain has an explicit root
directory, then it is modified to be relative to the toolchain's `bin` directory. Otherwise,
if it is an absolute path, a relative path with multiple path components, or a `File` object,
then it is executed as-is.

<a name="swift_common.run_toolchain_action.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.run_toolchain_action.actions">
      <td><code>actions</code></td>
      <td><p><code>Required</code></p><p>The <code>Actions</code> object with which to register actions.</p></td>
    </tr>
    <tr id="swift_common.run_toolchain_action.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider that prescribes the action's requirements.</p></td>
    </tr>
    <tr id="swift_common.run_toolchain_action.**kwargs">
      <td><code>**kwargs</code></td>
      <td><p>Additional arguments to <code>actions.run</code>.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.run_toolchain_shell_action"></a>
## swift_common.run_toolchain_shell_action

<pre style="white-space: normal">
swift_common.run_toolchain_shell_action(<a href="#swift_common.run_toolchain_shell_action.actions">actions</a>, <a href="#swift_common.run_toolchain_shell_action.toolchain">toolchain</a>, <a href="#swift_common.run_toolchain_shell_action.**kwargs">**kwargs</a>)
</pre>

Equivalent to `actions.run_shell`, but respecting toolchain settings.

This function applies the toolchain's environment and execution requirements and also wraps the
command in a wrapper executable if the toolchain requires it (for example, `xcrun` on Darwin).

<a name="swift_common.run_toolchain_shell_action.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.run_toolchain_shell_action.actions">
      <td><code>actions</code></td>
      <td><p><code>Required</code></p><p>The <code>Actions</code> object with which to register actions.</p></td>
    </tr>
    <tr id="swift_common.run_toolchain_shell_action.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider that prescribes the action's
requirements.</p></td>
    </tr>
    <tr id="swift_common.run_toolchain_shell_action.**kwargs">
      <td><code>**kwargs</code></td>
      <td><p>Additional arguments to <code>actions.run_shell</code>.</p></td>
    </tr>
  </tbody>
</table>

<a name="swift_common.run_toolchain_swift_action"></a>
## swift_common.run_toolchain_swift_action

<pre style="white-space: normal">
swift_common.run_toolchain_swift_action(<a href="#swift_common.run_toolchain_swift_action.actions">actions</a>, <a href="#swift_common.run_toolchain_swift_action.swift_tool">swift_tool</a>, <a href="#swift_common.run_toolchain_swift_action.toolchain">toolchain</a>, <a href="#swift_common.run_toolchain_swift_action.**kwargs">**kwargs</a>)
</pre>

Executes a Swift toolchain tool using its wrapper.

This function applies the toolchain's environment and execution requirements and wraps the
command in a toolchain-specific wrapper if necessary (for example, `xcrun` on Darwin) and in
additional pre- and post-processing to handle certain tasks like debug prefix remapping and
module cache health.

If the `swift_tool` argument is a simple basename and the toolchain has an explicit root
directory, then it is modified to be relative to the toolchain's `bin` directory. Otherwise,
if it is an absolute path, a relative path with multiple path components, or a `File` object,
then it is executed as-is.

<a name="swift_common.run_toolchain_swift_action.arguments"></a>
### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.run_toolchain_swift_action.actions">
      <td><code>actions</code></td>
      <td><p><code>Required</code></p><p>The <code>Actions</code> object with which to register actions.</p></td>
    </tr>
    <tr id="swift_common.run_toolchain_swift_action.swift_tool">
      <td><code>swift_tool</code></td>
      <td><p><code>Required</code></p><p>The name of the Swift tool to invoke.</p></td>
    </tr>
    <tr id="swift_common.run_toolchain_swift_action.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>The <code>SwiftToolchainInfo</code> provider that prescribes the action's requirements.</p></td>
    </tr>
    <tr id="swift_common.run_toolchain_swift_action.**kwargs">
      <td><code>**kwargs</code></td>
      <td><p>Additional arguments to <code>actions.run</code>.</p></td>
    </tr>
  </tbody>
</table>

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
swift_common.swiftc_command_line_and_inputs(<a href="#swift_common.swiftc_command_line_and_inputs.args">args</a>, <a href="#swift_common.swiftc_command_line_and_inputs.compilation_mode">compilation_mode</a>, <a href="#swift_common.swiftc_command_line_and_inputs.module_name">module_name</a>, <a href="#swift_common.swiftc_command_line_and_inputs.srcs">srcs</a>,
<a href="#swift_common.swiftc_command_line_and_inputs.swift_fragment">swift_fragment</a>, <a href="#swift_common.swiftc_command_line_and_inputs.toolchain">toolchain</a>, <a href="#swift_common.swiftc_command_line_and_inputs.additional_input_depsets">additional_input_depsets</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.allow_testing">allow_testing</a>=True, <a href="#swift_common.swiftc_command_line_and_inputs.configuration">configuration</a>=None,
<a href="#swift_common.swiftc_command_line_and_inputs.copts">copts</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.defines">defines</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.deps">deps</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.feature_configuration">feature_configuration</a>=None, <a href="#swift_common.swiftc_command_line_and_inputs.genfiles_dir">genfiles_dir</a>=None, <a href="#swift_common.swiftc_command_line_and_inputs.objc_fragment">objc_fragment</a>=None)
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
    <tr id="swift_common.swiftc_command_line_and_inputs.compilation_mode">
      <td><code>compilation_mode</code></td>
      <td><p><code>Required</code></p><p>The Bazel compilation mode; must be <code>dbg</code>, <code>fastbuild</code>, or
<code>opt</code>.</p></td>
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
    <tr id="swift_common.swiftc_command_line_and_inputs.swift_fragment">
      <td><code>swift_fragment</code></td>
      <td><p><code>Required</code></p><p>The <code>swift</code> configuration fragment from Bazel.</p></td>
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
    <tr id="swift_common.swiftc_command_line_and_inputs.allow_testing">
      <td><code>allow_testing</code></td>
      <td><p><code>Optional; default is True</code></p><p>Indicates whether the module should be compiled with testing
enabled (only when the compilation mode is <code>fastbuild</code> or <code>dbg</code>).</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.configuration">
      <td><code>configuration</code></td>
      <td><p><code>Optional; default is None</code></p><p>The default configuration from which certain compilation
options are determined, such as whether coverage is enabled. This object
should be one obtained from a rule's <code>ctx.configuraton</code> field. If
omitted, no default-configuration-specific options will be used.</p></td>
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
propagate one of the following providers: <code>SwiftClangModuleInfo</code>,
<code>SwiftInfo</code>, <code>"cc"</code>, or <code>apple_common.Objc</code>.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.feature_configuration">
      <td><code>feature_configuration</code></td>
      <td><p><code>Optional; default is None</code></p><p>A feature configuration obtained from
<code>swift_common.configure_features</code>. If omitted, a default feature
configuration will be used, but this argument will be required in the
future.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.genfiles_dir">
      <td><code>genfiles_dir</code></td>
      <td><p><code>Optional; default is None</code></p><p>The Bazel <code>*-genfiles</code> directory root. If provided, its path
is added to ClangImporter's header search paths for compatibility with
Bazel's C++ and Objective-C rules which support inclusions of generated
headers from that location.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.objc_fragment">
      <td><code>objc_fragment</code></td>
      <td><p><code>Optional; default is None</code></p><p>The <code>objc</code> configuration fragment from Bazel. This must be
provided if the toolchain supports Objective-C interop; if it does not,
then this argument may be omitted.</p></td>
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



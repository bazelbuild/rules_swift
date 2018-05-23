# Build API


The `swift_common` module provides API access to the behavior implemented
by the Swift build rules, so that other custom rules can invoke Swift
compilation and/or linking as part of their implementation.



<a href="swift_common.compilation_mode_copts"></a>
## swift_common.compilation_mode_copts

<pre style="white-space: pre-wrap">
swift_common.compilation_mode_copts(<a href="#swift_common.compilation_mode_copts.allow_testing">allow_testing</a>, <a href="#swift_common.compilation_mode_copts.compilation_mode">compilation_mode</a>)
</pre>

Returns `swiftc` compilation flags that match the given compilation mode.

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
  </tbody>
</table>

### Returns

A list of strings containing copts that should be passed to Swift.

<a href="swift_common.compile_as_library"></a>
## swift_common.compile_as_library

<pre style="white-space: pre-wrap">
swift_common.compile_as_library(<a href="#swift_common.compile_as_library.actions">actions</a>, <a href="#swift_common.compile_as_library.bin_dir">bin_dir</a>, <a href="#swift_common.compile_as_library.compilation_mode">compilation_mode</a>, <a href="#swift_common.compile_as_library.label">label</a>, <a href="#swift_common.compile_as_library.module_name">module_name</a>, <a href="#swift_common.compile_as_library.srcs">srcs</a>, <a href="#swift_common.compile_as_library.swift_fragment">swift_fragment</a>, <a href="#swift_common.compile_as_library.toolchain_target">toolchain_target</a>, <a href="#swift_common.compile_as_library.additional_inputs">additional_inputs</a>=[], <a href="#swift_common.compile_as_library.allow_testing">allow_testing</a>=True, <a href="#swift_common.compile_as_library.cc_libs">cc_libs</a>=[], <a href="#swift_common.compile_as_library.configuration">configuration</a>=None, <a href="#swift_common.compile_as_library.copts">copts</a>=[], <a href="#swift_common.compile_as_library.defines">defines</a>=[], <a href="#swift_common.compile_as_library.deps">deps</a>=[], <a href="#swift_common.compile_as_library.features">features</a>=[], <a href="#swift_common.compile_as_library.library_name">library_name</a>=None, <a href="#swift_common.compile_as_library.linkopts">linkopts</a>=[], <a href="#swift_common.compile_as_library.objc_fragment">objc_fragment</a>=None)
</pre>

Compiles Swift source files into static and/or shared libraries.

This is a high-level API that wraps the compilation and library creation steps
based on the provided input arguments, and is likely suitable for most common
purposes.

If the toolchain supports Objective-C interop, then this function also
generates an Objective-C header file for the library and returns an `Objc`
provider that allows other `objc_library` targets to depend on it.

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
    <tr id="swift_common.compile_as_library.toolchain_target">
      <td><code>toolchain_target</code></td>
      <td><p><code>Required</code></p><p>The target representing the Swift toolchain (which
propagates a <code>SwiftToolchainInfo</code> provider).</p></td>
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
    <tr id="swift_common.compile_as_library.features">
      <td><code>features</code></td>
      <td><p><code>Optional; default is []</code></p><p>Features that are enabled on the target being compiled.</p></td>
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

<a href="swift_common.compile_as_objects"></a>
## swift_common.compile_as_objects

<pre style="white-space: pre-wrap">
swift_common.compile_as_objects(<a href="#swift_common.compile_as_objects.actions">actions</a>, <a href="#swift_common.compile_as_objects.arguments">arguments</a>, <a href="#swift_common.compile_as_objects.compilation_mode">compilation_mode</a>, <a href="#swift_common.compile_as_objects.module_name">module_name</a>, <a href="#swift_common.compile_as_objects.srcs">srcs</a>, <a href="#swift_common.compile_as_objects.swift_fragment">swift_fragment</a>, <a href="#swift_common.compile_as_objects.target_name">target_name</a>, <a href="#swift_common.compile_as_objects.toolchain_target">toolchain_target</a>, <a href="#swift_common.compile_as_objects.additional_input_depsets">additional_input_depsets</a>=[], <a href="#swift_common.compile_as_objects.additional_outputs">additional_outputs</a>=[], <a href="#swift_common.compile_as_objects.allow_testing">allow_testing</a>=True, <a href="#swift_common.compile_as_objects.configuration">configuration</a>=None, <a href="#swift_common.compile_as_objects.copts">copts</a>=[], <a href="#swift_common.compile_as_objects.defines">defines</a>=[], <a href="#swift_common.compile_as_objects.deps">deps</a>=[], <a href="#swift_common.compile_as_objects.features">features</a>=[], <a href="#swift_common.compile_as_objects.objc_fragment">objc_fragment</a>=None)
</pre>

Compiles Swift source files into object files (and optionally a module).

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
    <tr id="swift_common.compile_as_objects.toolchain_target">
      <td><code>toolchain_target</code></td>
      <td><p><code>Required</code></p><p>The target representing the Swift toolchain (which
propagates a <code>SwiftToolchainInfo</code> provider).</p></td>
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
    <tr id="swift_common.compile_as_objects.features">
      <td><code>features</code></td>
      <td><p><code>Optional; default is []</code></p><p>Features that are enabled on the target being compiled.</p></td>
    </tr>
    <tr id="swift_common.compile_as_objects.objc_fragment">
      <td><code>objc_fragment</code></td>
      <td><p><code>Optional; default is None</code></p><p>The <code>objc</code> configuration fragment from Bazel. This must be
provided if the toolchain supports Objective-C interop; if it does not,
then this argument may be omitted.</p></td>
    </tr>
  </tbody>
</table>

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

<a href="swift_common.derive_module_name"></a>
## swift_common.derive_module_name

<pre style="white-space: pre-wrap">
swift_common.derive_module_name(<a href="#swift_common.derive_module_name.*args">*args</a>)
</pre>

Returns a derived module name from the given build label.

For targets whose module name is not explicitly specified, the module name is
computed by creating an underscore-delimited string from the components of the
label, replacing any non-identifier characters also with underscores.

This mapping is not intended to be reversible.

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

### Returns

The module name derived from the label.

<a href="swift_common.invoke_swiftc"></a>
## swift_common.invoke_swiftc

<pre style="white-space: pre-wrap">
swift_common.invoke_swiftc(<a href="#swift_common.invoke_swiftc.actions">actions</a>, <a href="#swift_common.invoke_swiftc.arguments">arguments</a>, <a href="#swift_common.invoke_swiftc.inputs">inputs</a>, <a href="#swift_common.invoke_swiftc.mnemonic">mnemonic</a>, <a href="#swift_common.invoke_swiftc.outputs">outputs</a>, <a href="#swift_common.invoke_swiftc.toolchain">toolchain</a>, <a href="#swift_common.invoke_swiftc.env">env</a>=None, <a href="#swift_common.invoke_swiftc.execution_requirements">execution_requirements</a>=None)
</pre>

Registers an action that invokes the Swift compiler.

This is a very low-level function that does minimal processing of the
arguments beyond ensuring that a wrapper script is applied to the invocation
if the toolchain requires it and that any toolchain-mandatory copts are
present. In particular, it does *not* automatically apply flags from Bazel's
Swift configuration fragment (i.e., `--swiftcopt` flags), nor any flags that
might be applied based on the Bazel `--compilation_mode`.

Most clients should prefer the higher-level `swift_common.compile_as_object`
or `swift_common.compile_as_library` instead.

### Arguments

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_common.invoke_swiftc.actions">
      <td><code>actions</code></td>
      <td><p><code>Required</code></p><p>The context's <code>actions</code> object.</p></td>
    </tr>
    <tr id="swift_common.invoke_swiftc.arguments">
      <td><code>arguments</code></td>
      <td><p><code>Required</code></p><p>A list of <code>Args</code> objects that should be passed to the command.</p></td>
    </tr>
    <tr id="swift_common.invoke_swiftc.inputs">
      <td><code>inputs</code></td>
      <td><p><code>Required</code></p><p>A list of <code>File</code>s that should be treated as inputs to the action.</p></td>
    </tr>
    <tr id="swift_common.invoke_swiftc.mnemonic">
      <td><code>mnemonic</code></td>
      <td><p><code>Required</code></p><p>The string mnemonic printed when the action is executed.</p></td>
    </tr>
    <tr id="swift_common.invoke_swiftc.outputs">
      <td><code>outputs</code></td>
      <td><p><code>Required</code></p><p>A list of <code>File</code>s that are the expected outputs of the action.</p></td>
    </tr>
    <tr id="swift_common.invoke_swiftc.toolchain">
      <td><code>toolchain</code></td>
      <td><p><code>Required</code></p><p>A <code>SwiftToolchainInfo</code> provider that contains information about
the toolchain being invoked.</p></td>
    </tr>
    <tr id="swift_common.invoke_swiftc.env">
      <td><code>env</code></td>
      <td><p><code>Optional; default is None</code></p><p>A dictionary of environment variables that should be set for the
spawned process. The toolchain's <code>action_environment</code> is also added to
this.</p></td>
    </tr>
    <tr id="swift_common.invoke_swiftc.execution_requirements">
      <td><code>execution_requirements</code></td>
      <td><p><code>Optional; default is None</code></p><p>Additional execution requirements for the action.
The toolchain's <code>execution_requirements</code> are also added to this.</p></td>
    </tr>
  </tbody>
</table>

<a href="swift_common.merge_swift_info_providers"></a>
## swift_common.merge_swift_info_providers

<pre style="white-space: pre-wrap">
swift_common.merge_swift_info_providers(<a href="#swift_common.merge_swift_info_providers.targets">targets</a>)
</pre>

Merges the transitive `SwiftInfo` of the given targets into a new provider.

This function should be used when it is necessary to merge `SwiftInfo`
providers outside of a compile action (which does it automatically).

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

### Returns

A new `SwiftInfo` provider that contains the transitive information from all
the targets.

<a href="swift_common.swiftc_command_line_and_inputs"></a>
## swift_common.swiftc_command_line_and_inputs

<pre style="white-space: pre-wrap">
swift_common.swiftc_command_line_and_inputs(<a href="#swift_common.swiftc_command_line_and_inputs.args">args</a>, <a href="#swift_common.swiftc_command_line_and_inputs.compilation_mode">compilation_mode</a>, <a href="#swift_common.swiftc_command_line_and_inputs.module_name">module_name</a>, <a href="#swift_common.swiftc_command_line_and_inputs.srcs">srcs</a>, <a href="#swift_common.swiftc_command_line_and_inputs.swift_fragment">swift_fragment</a>, <a href="#swift_common.swiftc_command_line_and_inputs.toolchain_target">toolchain_target</a>, <a href="#swift_common.swiftc_command_line_and_inputs.additional_input_depsets">additional_input_depsets</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.allow_testing">allow_testing</a>=True, <a href="#swift_common.swiftc_command_line_and_inputs.configuration">configuration</a>=None, <a href="#swift_common.swiftc_command_line_and_inputs.copts">copts</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.defines">defines</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.deps">deps</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.features">features</a>=[], <a href="#swift_common.swiftc_command_line_and_inputs.objc_fragment">objc_fragment</a>=None)
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
    <tr id="swift_common.swiftc_command_line_and_inputs.toolchain_target">
      <td><code>toolchain_target</code></td>
      <td><p><code>Required</code></p><p>The target representing the Swift toolchain (which
propagates a <code>SwiftToolchainInfo</code> provider).</p></td>
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
    <tr id="swift_common.swiftc_command_line_and_inputs.features">
      <td><code>features</code></td>
      <td><p><code>Optional; default is []</code></p><p>Features that are enabled on the target being compiled.</p></td>
    </tr>
    <tr id="swift_common.swiftc_command_line_and_inputs.objc_fragment">
      <td><code>objc_fragment</code></td>
      <td><p><code>Optional; default is None</code></p><p>The <code>objc</code> configuration fragment from Bazel. This must be
provided if the toolchain supports Objective-C interop; if it does not,
then this argument may be omitted.</p></td>
    </tr>
  </tbody>
</table>

### Returns

A `depset` containing the full set of files that need to be passed as inputs
of the Bazel action that spawns a tool with the computed command line (i.e.,
any source files, referenced module maps and headers, and so forth.)



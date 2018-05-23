# BUILD Rule Reference


<a href="swift_binary"></a>
## swift_binary

<pre style="white-space: pre-wrap">
swift_binary(<a href="#swift_binary.name">name</a>, <a href="#swift_binary.deps">deps</a>, <a href="#swift_binary.srcs">srcs</a>, <a href="#swift_binary.data">data</a>, <a href="#swift_binary.cc_libs">cc_libs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="#swift_binary.copts">copts</a>, <a href="#swift_binary.defines">defines</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_binary.linkopts">linkopts</a>, <a href="#swift_binary.module_name">module_name</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="#swift_binary.swiftc_inputs">swiftc_inputs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>

Compiles and links Swift code into an executable binary.

### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_binary.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
    <tr id="swift_binary.deps">
      <td><code>deps</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of targets that are dependencies of the target being built, which will be
linked into that target. Allowed kinds of dependencies are:</p>
<ul>
<li><code>swift_c_module</code> (or anything propagating <code>SwiftClangModuleInfo</code>)</li>
<li><code>swift_import</code> and <code>swift_library</code> (or anything propagating <code>SwiftInfo</code>)</li>
<li><code>cc_library</code> (or anything propagating <code>"cc"</code>)</li>
</ul>
<p>Additionally, on platforms that support Objective-C interop, <code>objc_library</code>
targets (or anything propagating the <code>apple_common.Objc</code> provider) are allowed
as dependencies. On platforms that do not support Objective-C interop (such as
Linux), those dependencies will be <strong>ignored.</strong></p></td>
    </tr>
    <tr id="swift_binary.srcs">
      <td><code>srcs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of <code>.swift</code> source files that will be compiled into the library.</p></td>
    </tr>
    <tr id="swift_binary.data">
      <td><code>data</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>The list of files needed by this target at runtime.</p>
<p>Files and targets named in the <code>data</code> attribute will appear in the <code>*.runfiles</code>
area of this target, if it has one. This may include data files needed by a
binary or library, or other programs needed by it.</p></td>
    </tr>
    <tr id="swift_binary.cc_libs">
      <td><code>cc_libs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of <code>cc_library</code> targets that should be <em>merged</em> with the static library
or binary produced by this target.</p>
<p>Most normal Swift use cases do not need to make use of this attribute. It is
intended to support cases where C and Swift code <em>must</em> exist in the same
archive; for example, a Swift function annotated with <code>@_cdecl</code> which is then
referenced from C code in the same library.</p></td>
    </tr>
    <tr id="swift_binary.copts">
      <td><code>copts</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>Additional compiler options that should be passed to <code>swiftc</code>. These strings are
subject to <code>$(location ...)</code> expansion.</p></td>
    </tr>
    <tr id="swift_binary.defines">
      <td><code>defines</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>A list of defines to add to the compilation command line.</p>
<p>Note that unlike C-family languages, Swift defines do not have values; they are
simply identifiers that are either defined or undefined. So strings in this list
should be simple identifiers, <strong>not</strong> <code>name=value</code> pairs.</p>
<p>Each string is prepended with <code>-D</code> and added to the command line. Unlike
<code>copts</code>, these flags are added for the target and every target that depends on
it, so use this attribute with caution. It is preferred that you add defines
directly to <code>copts</code>, only using this feature in the rare case that a library
needs to propagate a symbol up to those that depend on it.</p></td>
    </tr>
    <tr id="swift_binary.linkopts">
      <td><code>linkopts</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>Additional linker options that should be passed to <code>clang</code>. These strings are
subject to <code>$(location ...)</code> expansion.</p></td>
    </tr>
    <tr id="swift_binary.module_name">
      <td><code>module_name</code></td>
      <td>
        <p><code>String; optional</code></p><p>The name of the Swift module being built.</p>
<p>If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading <code>//</code> and replacing <code>/</code>, <code>:</code>, and other
non-identifier characters with underscores.</p></td>
    </tr>
    <tr id="swift_binary.swiftc_inputs">
      <td><code>swiftc_inputs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Additional files that are referenced using <code>$(location ...)</code> in attributes that
support location expansion.</p></td>
    </tr>
  </tbody>
</table>


<a href="swift_c_module"></a>
## swift_c_module

<pre style="white-space: pre-wrap">
swift_c_module(<a href="#swift_c_module.name">name</a>, <a href="#swift_c_module.deps">deps</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_c_module.module_map">module_map</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>


Wraps a `cc_library` in a new module map that allows it to be imported into
Swift to access its C interfaces.

NOTE: Swift at this time does not support interop directly with C++. Any headers
referenced by a module map that is imported into Swift must have only C features
visible, often by using preprocessor conditions like `#if __cplusplus` to hide
any C++ declarations.

The `cc_library` rule in Bazel does not produce module maps that are compatible
with Swift. In order to make interop between Swift and C possible, users can
write their own module map that includes any of the transitive public headers of
the `cc_library` dependency of this target and has a module name that is a valid
Swift identifier.

Then, write a `swift_{binary,library,test}` target that depends on this
`swift_c_module` target and the Swift sources will be able to import the module
with the name given in the module map.


### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_c_module.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
    <tr id="swift_c_module.deps">
      <td><code>deps</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; required</code></p><p>A list containing at most one <code>cc_library</code> target that is being wrapped with a
new module map.</p>
<p>If you need to create a <code>swift_c_module</code> to that pulls headers from multiple
<code>cc_library</code> targets into a single module, create a new <code>cc_library</code> target
that wraps them in its <code>deps</code> and has no other <code>srcs</code> or <code>hdrs</code>, and have the
module target depend on that.</p></td>
    </tr>
    <tr id="swift_c_module.module_map">
      <td><code>module_map</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#labels">Label</a>; required</code></p><p>The module map file that should be loaded to import the C library dependency
into Swift.</p></td>
    </tr>
  </tbody>
</table>


<a href="swift_import"></a>
## swift_import

<pre style="white-space: pre-wrap">
swift_import(<a href="#swift_import.name">name</a>, <a href="#swift_import.deps">deps</a>, <a href="#swift_import.data">data</a>, <a href="#swift_import.archives">archives</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="#swift_import.swiftmodules">swiftmodules</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>


Allows for the use of precompiled Swift modules as dependencies in other
`swift_library` and `swift_binary` targets.


### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_import.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
    <tr id="swift_import.deps">
      <td><code>deps</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of targets that are dependencies of the target being built, which will be
linked into that target. Allowed kinds of dependencies are:</p>
<ul>
<li><code>swift_c_module</code> (or anything propagating <code>SwiftClangModuleInfo</code>)</li>
<li><code>swift_import</code> and <code>swift_library</code> (or anything propagating <code>SwiftInfo</code>)</li>
<li><code>cc_library</code> (or anything propagating <code>"cc"</code>)</li>
</ul>
<p>Additionally, on platforms that support Objective-C interop, <code>objc_library</code>
targets (or anything propagating the <code>apple_common.Objc</code> provider) are allowed
as dependencies. On platforms that do not support Objective-C interop (such as
Linux), those dependencies will be <strong>ignored.</strong></p></td>
    </tr>
    <tr id="swift_import.data">
      <td><code>data</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>The list of files needed by this target at runtime.</p>
<p>Files and targets named in the <code>data</code> attribute will appear in the <code>*.runfiles</code>
area of this target, if it has one. This may include data files needed by a
binary or library, or other programs needed by it.</p></td>
    </tr>
    <tr id="swift_import.archives">
      <td><code>archives</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; required</code></p><p>The list of <code>.a</code> files provided to Swift targets that depend on this target.</p></td>
    </tr>
    <tr id="swift_import.swiftmodules">
      <td><code>swiftmodules</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; required</code></p><p>The list of <code>.swiftmodule</code> files provided to Swift targets that depend on this
target.</p></td>
    </tr>
  </tbody>
</table>


<a href="swift_library"></a>
## swift_library

<pre style="white-space: pre-wrap">
swift_library(<a href="#swift_library.name">name</a>, <a href="#swift_library.deps">deps</a>, <a href="#swift_library.srcs">srcs</a>, <a href="#swift_library.data">data</a>, <a href="#swift_library.cc_libs">cc_libs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="#swift_library.copts">copts</a>, <a href="#swift_library.defines">defines</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_library.linkopts">linkopts</a>, <a href="#swift_library.module_link_name">module_link_name</a>, <a href="#swift_library.module_name">module_name</a>, <a href="#swift_library.resources">resources</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="#swift_library.structured_resources">structured_resources</a>, <a href="#swift_library.swiftc_inputs">swiftc_inputs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>


Compiles and links Swift code into a static library and Swift module.


### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_library.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
    <tr id="swift_library.deps">
      <td><code>deps</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of targets that are dependencies of the target being built, which will be
linked into that target. Allowed kinds of dependencies are:</p>
<ul>
<li><code>swift_c_module</code> (or anything propagating <code>SwiftClangModuleInfo</code>)</li>
<li><code>swift_import</code> and <code>swift_library</code> (or anything propagating <code>SwiftInfo</code>)</li>
<li><code>cc_library</code> (or anything propagating <code>"cc"</code>)</li>
</ul>
<p>Additionally, on platforms that support Objective-C interop, <code>objc_library</code>
targets (or anything propagating the <code>apple_common.Objc</code> provider) are allowed
as dependencies. On platforms that do not support Objective-C interop (such as
Linux), those dependencies will be <strong>ignored.</strong></p></td>
    </tr>
    <tr id="swift_library.srcs">
      <td><code>srcs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of <code>.swift</code> source files that will be compiled into the library.</p></td>
    </tr>
    <tr id="swift_library.data">
      <td><code>data</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>The list of files needed by this target at runtime.</p>
<p>Files and targets named in the <code>data</code> attribute will appear in the <code>*.runfiles</code>
area of this target, if it has one. This may include data files needed by a
binary or library, or other programs needed by it.</p></td>
    </tr>
    <tr id="swift_library.cc_libs">
      <td><code>cc_libs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of <code>cc_library</code> targets that should be <em>merged</em> with the static library
or binary produced by this target.</p>
<p>Most normal Swift use cases do not need to make use of this attribute. It is
intended to support cases where C and Swift code <em>must</em> exist in the same
archive; for example, a Swift function annotated with <code>@_cdecl</code> which is then
referenced from C code in the same library.</p></td>
    </tr>
    <tr id="swift_library.copts">
      <td><code>copts</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>Additional compiler options that should be passed to <code>swiftc</code>. These strings are
subject to <code>$(location ...)</code> expansion.</p></td>
    </tr>
    <tr id="swift_library.defines">
      <td><code>defines</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>A list of defines to add to the compilation command line.</p>
<p>Note that unlike C-family languages, Swift defines do not have values; they are
simply identifiers that are either defined or undefined. So strings in this list
should be simple identifiers, <strong>not</strong> <code>name=value</code> pairs.</p>
<p>Each string is prepended with <code>-D</code> and added to the command line. Unlike
<code>copts</code>, these flags are added for the target and every target that depends on
it, so use this attribute with caution. It is preferred that you add defines
directly to <code>copts</code>, only using this feature in the rare case that a library
needs to propagate a symbol up to those that depend on it.</p></td>
    </tr>
    <tr id="swift_library.linkopts">
      <td><code>linkopts</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>Additional linker options that should be passed to the linker for the binary
that depends on this target. These strings are subject to <code>$(location ...)</code>
expansion.</p></td>
    </tr>
    <tr id="swift_library.module_link_name">
      <td><code>module_link_name</code></td>
      <td>
        <p><code>String; optional</code></p><p>The name of the library that should be linked to targets that depend on this
library. Supports auto-linking.</p></td>
    </tr>
    <tr id="swift_library.module_name">
      <td><code>module_name</code></td>
      <td>
        <p><code>String; optional</code></p><p>The name of the Swift module being built.</p>
<p>If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading <code>//</code> and replacing <code>/</code>, <code>:</code>, and other
non-identifier characters with underscores.</p></td>
    </tr>
    <tr id="swift_library.resources">
      <td><code>resources</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Resources that should be processed by Xcode tools (such as interface builder
documents, Core Data models, asset catalogs, and so forth) and included in the
bundle that depends on this library.</p>
<p>This attribute is ignored when building Linux targets.</p></td>
    </tr>
    <tr id="swift_library.structured_resources">
      <td><code>structured_resources</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Files that should be included in the bundle that depends on this library without
any additional processing. The paths of these files relative to this library
target are preserved inside the bundle.</p>
<p>This attribute is ignored when building Linux targets.</p></td>
    </tr>
    <tr id="swift_library.swiftc_inputs">
      <td><code>swiftc_inputs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Additional files that are referenced using <code>$(location ...)</code> in attributes that
support location expansion.</p></td>
    </tr>
  </tbody>
</table>


<a href="swift_test"></a>
## swift_test

<pre style="white-space: pre-wrap">
swift_test(<a href="#swift_test.name">name</a>, <a href="#swift_test.deps">deps</a>, <a href="#swift_test.srcs">srcs</a>, <a href="#swift_test.data">data</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.args">args</a>, <a href="#swift_test.cc_libs">cc_libs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="#swift_test.copts">copts</a>, <a href="#swift_test.defines">defines</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.flaky">flaky</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_test.linkopts">linkopts</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.local">local</a>, <a href="#swift_test.module_name">module_name</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.shardcount">shardcount</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.size">size</a>, <a href="#swift_test.swiftc_inputs">swiftc_inputs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.timeout">timeout</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>

Compiles and links Swift code into an executable test target.

### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_test.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
    <tr id="swift_test.deps">
      <td><code>deps</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of targets that are dependencies of the target being built, which will be
linked into that target. Allowed kinds of dependencies are:</p>
<ul>
<li><code>swift_c_module</code> (or anything propagating <code>SwiftClangModuleInfo</code>)</li>
<li><code>swift_import</code> and <code>swift_library</code> (or anything propagating <code>SwiftInfo</code>)</li>
<li><code>cc_library</code> (or anything propagating <code>"cc"</code>)</li>
</ul>
<p>Additionally, on platforms that support Objective-C interop, <code>objc_library</code>
targets (or anything propagating the <code>apple_common.Objc</code> provider) are allowed
as dependencies. On platforms that do not support Objective-C interop (such as
Linux), those dependencies will be <strong>ignored.</strong></p></td>
    </tr>
    <tr id="swift_test.srcs">
      <td><code>srcs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of <code>.swift</code> source files that will be compiled into the library.</p></td>
    </tr>
    <tr id="swift_test.data">
      <td><code>data</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>The list of files needed by this target at runtime.</p>
<p>Files and targets named in the <code>data</code> attribute will appear in the <code>*.runfiles</code>
area of this target, if it has one. This may include data files needed by a
binary or library, or other programs needed by it.</p></td>
    </tr>
    <tr id="swift_test.cc_libs">
      <td><code>cc_libs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of <code>cc_library</code> targets that should be <em>merged</em> with the static library
or binary produced by this target.</p>
<p>Most normal Swift use cases do not need to make use of this attribute. It is
intended to support cases where C and Swift code <em>must</em> exist in the same
archive; for example, a Swift function annotated with <code>@_cdecl</code> which is then
referenced from C code in the same library.</p></td>
    </tr>
    <tr id="swift_test.copts">
      <td><code>copts</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>Additional compiler options that should be passed to <code>swiftc</code>. These strings are
subject to <code>$(location ...)</code> expansion.</p></td>
    </tr>
    <tr id="swift_test.defines">
      <td><code>defines</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>A list of defines to add to the compilation command line.</p>
<p>Note that unlike C-family languages, Swift defines do not have values; they are
simply identifiers that are either defined or undefined. So strings in this list
should be simple identifiers, <strong>not</strong> <code>name=value</code> pairs.</p>
<p>Each string is prepended with <code>-D</code> and added to the command line. Unlike
<code>copts</code>, these flags are added for the target and every target that depends on
it, so use this attribute with caution. It is preferred that you add defines
directly to <code>copts</code>, only using this feature in the rare case that a library
needs to propagate a symbol up to those that depend on it.</p></td>
    </tr>
    <tr id="swift_test.linkopts">
      <td><code>linkopts</code></td>
      <td>
        <p><code>List of strings; optional</code></p><p>Additional linker options that should be passed to <code>clang</code>. These strings are
subject to <code>$(location ...)</code> expansion.</p></td>
    </tr>
    <tr id="swift_test.module_name">
      <td><code>module_name</code></td>
      <td>
        <p><code>String; optional</code></p><p>The name of the Swift module being built.</p>
<p>If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading <code>//</code> and replacing <code>/</code>, <code>:</code>, and other
non-identifier characters with underscores.</p></td>
    </tr>
    <tr id="swift_test.swiftc_inputs">
      <td><code>swiftc_inputs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Additional files that are referenced using <code>$(location ...)</code> in attributes that
support location expansion.</p></td>
    </tr>
  </tbody>
</table>


<a href="swift_module_alias"></a>
## swift_module_alias

<pre style="white-space: pre-wrap">
swift_module_alias(<a href="#swift_module_alias.name">name</a>, <a href="#swift_module_alias.deps">deps</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_module_alias.module_name">module_name</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>


Creates a Swift module that re-exports other modules.

This rule effectively creates an "alias" for one or more modules such that a
client can import the alias module and it will implicitly import those
dependencies. It should be used primarily as a way to migrate users when a
module name is being changed. An alias that depends on more than one module can
be used to split a large module into smaller, more targeted modules.

Symbols in the original modules can be accessed through either the original
module name or the alias module name, so callers can be migrated separately
after moving the physical build target as needed. (An exception to this is
runtime type metadata, which only encodes the module name of the type where the
symbol is defined; it is not repeated by the alias module.)

This rule unconditionally prints a message directing users to migrate from the
alias to the aliased modules---this is intended to prevent misuse of this rule
to create "umbrella modules".

> Caution: This rule uses the undocumented `@_exported` feature to re-export the
> `deps` in the new module. You depend on undocumented features at your own
> risk, as they may change in a future version of Swift.


### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_module_alias.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
    <tr id="swift_module_alias.deps">
      <td><code>deps</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>A list of targets that are dependencies of the target being built, which will be
linked into that target. Allowed kinds are <code>swift_import</code> and <code>swift_library</code>
(or anything else propagating <code>SwiftInfo</code>).</p></td>
    </tr>
    <tr id="swift_module_alias.module_name">
      <td><code>module_name</code></td>
      <td>
        <p><code>String; optional</code></p><p>The name of the Swift module being built.</p>
<p>If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading <code>//</code> and replacing <code>/</code>, <code>:</code>, and other
non-identifier characters with underscores.</p></td>
    </tr>
  </tbody>
</table>


<a href="swift_proto_library"></a>
## swift_proto_library

<pre style="white-space: pre-wrap">
swift_proto_library(<a href="#swift_proto_library.name">name</a>, <a href="#swift_proto_library.deps">deps</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>


Generates a Swift library from protocol buffer sources.

There should be one `swift_proto_library` for any `proto_library` that you wish
to depend on. A target based on this rule can be used as a dependency anywhere
that a `swift_library` can be used.

A `swift_proto_library` target only creates a Swift module if the
`proto_library` on which it depends has a non-empty `srcs` attribute. If the
`proto_library` does not contain `srcs`, then no module is produced, but the
`swift_proto_library` still propagates the modules of its non-empty dependencies
so that those generated protos can be used by depending on the
`swift_proto_library` of the "collector" target.

Convention is to put the `swift_proto_library` in the same `BUILD` file as
the `proto_library` it is generating for (just like all the other
`LANG_proto_library` rules). This lets anyone needing the protos in Swift
share the single rule as well as making it easier to realize what proto
files are in use in what contexts.

Note that the module name of the Swift library produced by this rule (if any)
is based on the name of the `proto_library` target, *not* the name of the
`swift_proto_library` target. In other words, if the following BUILD file were
located in `//my/pkg`, the target would create a Swift module named
`my_pkg_foo`:

```
proto_library(
    name = "foo",
    srcs = ["foo.proto"],
)

swift_proto_library(
    name = "foo_swift",
    deps = [":foo"],
)
```


### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_proto_library.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
    <tr id="swift_proto_library.deps">
      <td><code>deps</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Exactly one <code>proto_library</code> target (or any target that propagates a <code>proto</code>
provider) from which the Swift library should be generated.</p></td>
    </tr>
  </tbody>
</table>


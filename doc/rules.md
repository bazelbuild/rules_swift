# BUILD Rule Reference

<!-- Generated file, do not edit directly. -->



To use the Swift build rules in your BUILD files, load them from
`@build_bazel_rules_swift//swift:swift.bzl`.

For example:

```build
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
```

On this page:

  * [swift_binary](#swift_binary)
  * [swift_c_module](#swift_c_module)
  * [swift_grpc_library](#swift_grpc_library)
  * [swift_import](#swift_import)
  * [swift_library](#swift_library)
  * [swift_module_alias](#swift_module_alias)
  * [swift_proto_library](#swift_proto_library)
  * [swift_test](#swift_test)
<a name="swift_binary"></a>
## swift_binary

<pre style="white-space: normal">
swift_binary(<a href="#swift_binary.name">name</a>, <a href="#swift_binary.deps">deps</a>, <a href="#swift_binary.srcs">srcs</a>, <a href="#swift_binary.data">data</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="#swift_binary.copts">copts</a>, <a href="#swift_binary.defines">defines</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_binary.linkopts">linkopts</a>, <a href="#swift_binary.malloc">malloc</a>, <a href="#swift_binary.module_name">module_name</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="#swift_binary.swiftc_inputs">swiftc_inputs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>

Compiles and links Swift code into an executable binary.

On Linux, this rule produces an executable binary for the desired target architecture.

On Apple platforms, this rule produces a _single-architecture_ binary; it does not produce fat
binaries. As such, this rule is mainly useful for creating Swift tools intended to run on the
local build machine. However, for historical reasons, the default Apple platform in Bazel is
**iOS** instead of macOS. Therefore, if you wish to build a simple single-architecture Swift
binary that can run on macOS, you must specify the correct CPU and platform on the command line as
follows:

```shell
$ bazel build //package:target
```

If you want to create a multi-architecture binary or a bundled application, please use one of the
platform-specific application rules in [rules_apple](https://github.com/bazelbuild/rules_apple)
instead of `swift_binary`.

<a name="swift_binary.attributes"></a>
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
<li><code>swift_c_module</code>, <code>swift_import</code> and <code>swift_library</code> (or anything propagating <code>SwiftInfo</code>)</li>
<li><code>cc_library</code> (or anything propagating <code>CcInfo</code>)</li>
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
        <p><code>List of strings; optional</code></p><p>Additional linker options that should be passed to <code>clang</code>. These strings are subject to
<code>$(location ...)</code> expansion.</p></td>
    </tr>
    <tr id="swift_binary.malloc">
      <td><code>malloc</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#labels">Label</a>; optional; default is @bazel_tools//tools/cpp:malloc</code></p><p>Override the default dependency on <code>malloc</code>.</p>
<p>By default, Swift binaries are linked against <code>@bazel_tools//tools/cpp:malloc"</code>, which is an empty
library and the resulting binary will use libc's <code>malloc</code>. This label must refer to a <code>cc_library</code>
rule.</p></td>
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


<a name="swift_c_module"></a>
## swift_c_module

<pre style="white-space: normal">
swift_c_module(<a href="#swift_c_module.name">name</a>, <a href="#swift_c_module.deps">deps</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_c_module.module_map">module_map</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
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

<a name="swift_c_module.attributes"></a>
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


<a name="swift_grpc_library"></a>
## swift_grpc_library

<pre style="white-space: normal">
swift_grpc_library(<a href="#swift_grpc_library.name">name</a>, <a href="#swift_grpc_library.deps">deps</a>, <a href="#swift_grpc_library.srcs">srcs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="#swift_grpc_library.flavor">flavor</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>

Generates a Swift library from the gRPC services defined in protocol buffer sources.

There should be one `swift_grpc_library` for any `proto_library` that defines services. A target
based on this rule can be used as a dependency anywhere that a `swift_library` can be used.

We recommend that `swift_grpc_library` targets be located in the same package as the
`proto_library` and `swift_proto_library` targets they depend on. For more best practices around
the use of Swift protocol buffer build rules, see the documentation for `swift_proto_library`.

#### Defining Build Targets for Services

Note that `swift_grpc_library` only generates the gRPC service interfaces (the `service`
definitions) from the `.proto` files. Any messages defined in the same `.proto` file must be
generated using a `swift_proto_library` target. Thus, the typical structure of a Swift gRPC
library is similar to the following:

```python
proto_library(
    name = "my_protos",
    srcs = ["my_protos.proto"],
)

# Generate Swift types from the protos.
swift_proto_library(
    name = "my_protos_swift",
    deps = [":my_protos"],
)

# Generate Swift types from the services.
swift_grpc_library(
    name = "my_protos_client_services_swift",
    # The `srcs` attribute points to the `proto_library` containing the service definitions...
    srcs = [":my_protos"],
    # ...the `flavor` attribute specifies what kind of definitions to generate...
    flavor = "client",
    # ...and the `deps` attribute points to the `swift_proto_library` that was generated from
    # the same `proto_library` and which contains the messages used by those services.
    deps = [":my_protos_swift"],
)

# Generate test stubs from swift services.
swift_grpc_library(
    name = "my_protos_client_stubs_swift",
    # The `srcs` attribute points to the `proto_library` containing the service definitions...
    srcs = [":my_protos"],
    # ...the `flavor` attribute specifies what kind of definitions to generate...
    flavor = "client_stubs",
    # ...and the `deps` attribute points to the `swift_grpc_library` that was generated from
    # the same `proto_library` and which contains the service implementation.
    deps = [":my_protos_client_services_swift"],
)
```

<a name="swift_grpc_library.attributes"></a>
### Attributes

<table class="params-table">
  <colgroup>
    <col class="col-param" />
    <col class="col-description" />
  </colgroup>
  <tbody>
    <tr id="swift_grpc_library.name">
      <td><code>name</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#name">Name</a>; required</code></p><p>A unique name for this target.</p></td>
    </tr>
    <tr id="swift_grpc_library.deps">
      <td><code>deps</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Exactly one <code>swift_proto_library</code> or <code>swift_grpc_library</code> target that contains the Swift protos
used by the services being generated. Test stubs should depend on the <code>swift_grpc_library</code>
implementing the service.</p></td>
    </tr>
    <tr id="swift_grpc_library.srcs">
      <td><code>srcs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Exactly one <code>proto_library</code> target that defines the services being generated.</p></td>
    </tr>
    <tr id="swift_grpc_library.flavor">
      <td><code>flavor</code></td>
      <td>
        <p><code>String; required; valid values are ['client', 'client_stubs', 'server']</code></p><p>The kind of definitions that should be generated:</p>
<ul>
<li><code>"client"</code> to generate client definitions.</li>
<li><code>"client_stubs"</code> to generate client test stubs.</li>
<li><code>"server"</code> to generate server definitions.</li>
</ul></td>
    </tr>
  </tbody>
</table>


<a name="swift_import"></a>
## swift_import

<pre style="white-space: normal">
swift_import(<a href="#swift_import.name">name</a>, <a href="#swift_import.deps">deps</a>, <a href="#swift_import.data">data</a>, <a href="#swift_import.archives">archives</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="#swift_import.swiftdocs">swiftdocs</a>, <a href="#swift_import.swiftmodules">swiftmodules</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>

Allows for the use of precompiled Swift modules as dependencies in other `swift_library` and
`swift_binary` targets.

<a name="swift_import.attributes"></a>
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
<li><code>swift_c_module</code>, <code>swift_import</code> and <code>swift_library</code> (or anything propagating <code>SwiftInfo</code>)</li>
<li><code>cc_library</code> (or anything propagating <code>CcInfo</code>)</li>
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
    <tr id="swift_import.swiftdocs">
      <td><code>swiftdocs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>The list of <code>.swiftdoc</code> files provided to Swift targets that depend on this target.</p></td>
    </tr>
    <tr id="swift_import.swiftmodules">
      <td><code>swiftmodules</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; required</code></p><p>The list of <code>.swiftmodule</code> files provided to Swift targets that depend on this target.</p></td>
    </tr>
  </tbody>
</table>


<a name="swift_library"></a>
## swift_library

<pre style="white-space: normal">
swift_library(<a href="#swift_library.name">name</a>, <a href="#swift_library.deps">deps</a>, <a href="#swift_library.srcs">srcs</a>, <a href="#swift_library.data">data</a>, <a href="#swift_library.alwayslink">alwayslink</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="#swift_library.copts">copts</a>, <a href="#swift_library.defines">defines</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_library.linkopts">linkopts</a>, <a href="#swift_library.module_name">module_name</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="#swift_library.swiftc_inputs">swiftc_inputs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>

Compiles and links Swift code into a static library and Swift module.

<a name="swift_library.attributes"></a>
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
<li><code>swift_c_module</code>, <code>swift_import</code> and <code>swift_library</code> (or anything propagating <code>SwiftInfo</code>)</li>
<li><code>cc_library</code> (or anything propagating <code>CcInfo</code>)</li>
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
    <tr id="swift_library.alwayslink">
      <td><code>alwayslink</code></td>
      <td>
        <p><code>Boolean; optional</code></p><p>If true, any binary that depends (directly or indirectly) on this Swift module
will link in all the object files for the files listed in <code>srcs</code>, even if some
contain no symbols referenced by the binary. This is useful if your code isn't
explicitly called by code in the binary; for example, if you rely on runtime
checks for protocol conformances added in extensions in the library but do not
directly reference any other symbols in the object file that adds that
conformance.</p></td>
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
    <tr id="swift_library.module_name">
      <td><code>module_name</code></td>
      <td>
        <p><code>String; optional</code></p><p>The name of the Swift module being built.</p>
<p>If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading <code>//</code> and replacing <code>/</code>, <code>:</code>, and other
non-identifier characters with underscores.</p></td>
    </tr>
    <tr id="swift_library.swiftc_inputs">
      <td><code>swiftc_inputs</code></td>
      <td>
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Additional files that are referenced using <code>$(location ...)</code> in attributes that
support location expansion.</p></td>
    </tr>
  </tbody>
</table>


<a name="swift_module_alias"></a>
## swift_module_alias

<pre style="white-space: normal">
swift_module_alias(<a href="#swift_module_alias.name">name</a>, <a href="#swift_module_alias.deps">deps</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>,
<a href="#swift_module_alias.module_name">module_name</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
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

> Caution: This rule uses the undocumented `@_exported` feature to re-export the
> `deps` in the new module. You depend on undocumented features at your own
> risk, as they may change in a future version of Swift.

<a name="swift_module_alias.attributes"></a>
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


<a name="swift_proto_library"></a>
## swift_proto_library

<pre style="white-space: normal">
swift_proto_library(<a href="#swift_proto_library.name">name</a>, <a href="#swift_proto_library.deps">deps</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>

Generates a Swift library from protocol buffer sources.

There should be one `swift_proto_library` for any `proto_library` that you wish to depend on. A
target based on this rule can be used as a dependency anywhere that a `swift_library` can be used.

A `swift_proto_library` target only creates a Swift module if the `proto_library` on which it
depends has a non-empty `srcs` attribute. If the `proto_library` does not contain `srcs`, then no
module is produced, but the `swift_proto_library` still propagates the modules of its non-empty
dependencies so that those generated protos can be used by depending on the `swift_proto_library`
of the "collector" target.

Note that the module name of the Swift library produced by this rule (if any) is based on the name
of the `proto_library` target, *not* the name of the `swift_proto_library` target. In other words,
if the following BUILD file were located in `//my/pkg`, the target would create a Swift module
named `my_pkg_foo`:

```python
proto_library(
    name = "foo",
    srcs = ["foo.proto"],
)

swift_proto_library(
    name = "foo_swift",
    deps = [":foo"],
)
```

Because the Swift modules are generated from an aspect that is applied to the `proto_library`
targets, the module name and other compilation flags for the resulting Swift modules cannot be
changed.

#### Tip: Where to locate `swift_proto_library` targets

Convention is to put the `swift_proto_library` in the same `BUILD` file as the `proto_library` it
is generating for (just like all the other `LANG_proto_library` rules). This lets anyone needing
the protos in Swift share the single rule as well as making it easier to realize what proto files
are in use in what contexts.

This is not a requirement, however, as it may not be possible for Bazel workspaces that create
`swift_proto_library` targets that depend on `proto_library` targets from different repositories.

#### Tip: Avoid `import` only `.proto` files

Avoid creating a `.proto` file that just contains `import` directives of all the other `.proto`
files you need. While this does _group_ the protos into this new target, it comes with some high
costs. This causes the proto compiler to parse all those files and invoke the generator for an
otherwise empty source file. That empty source file then has to get compiled, but it will have
dependencies on the full deps chain of the imports (recursively). The Swift compiler must load
all of these module dependencies, which can be fairly slow if there are many of them, so this
method of grouping via a `.proto` file actually ends up creating build steps that slow down the
build.

#### Tip: Resolving unused import warnings

If you see warnings like the following during your build:

```
path/file.proto: warning: Import other/path/file.proto but not used.
```

The proto compiler is letting you know that you have an `import` statement loading a file from
which nothing is used, so it is wasted work. The `import` can be removed (in this case,
`import other/path/file.proto` could be removed from `path/file.proto`). These warnings can also
mean that the `proto_library` has `deps` that aren't needed. Removing those along with the
`import` statement(s) will speed up downstream Swift compilation actions, because it prevents
unused modules from being loaded by `swiftc`.

<a name="swift_proto_library.attributes"></a>
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
        <p><code>List of <a hef="https://docs.bazel.build/versions/master/build-ref.html#labels">labels</a>; optional</code></p><p>Exactly one <code>proto_library</code> target (or any target that propagates a <code>proto</code> provider) from which
the Swift library should be generated.</p></td>
    </tr>
  </tbody>
</table>


<a name="swift_test"></a>
## swift_test

<pre style="white-space: normal">
swift_test(<a href="#swift_test.name">name</a>, <a href="#swift_test.deps">deps</a>, <a href="#swift_test.srcs">srcs</a>, <a href="#swift_test.data">data</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.args">args</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.compatible_with">compatible_with</a>, <a href="#swift_test.copts">copts</a>, <a href="#swift_test.defines">defines</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.deprecation">deprecation</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.distribs">distribs</a>,
<a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.features">features</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.flaky">flaky</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.licenses">licenses</a>, <a href="#swift_test.linkopts">linkopts</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.local">local</a>, <a href="#swift_test.malloc">malloc</a>, <a href="#swift_test.module_name">module_name</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.restricted_to">restricted_to</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.shardcount">shardcount</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.size">size</a>,
<a href="#swift_test.swiftc_inputs">swiftc_inputs</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.tags">tags</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.testonly">testonly</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#test.timeout">timeout</a>, <a href="https://docs.bazel.build/versions/master/be/common-definitions.html#common.visibility">visibility</a>)
</pre>

Compiles and links Swift code into an executable test target.

The behavior of `swift_test` differs slightly for macOS targets, in order to provide seamless
integration with Apple's XCTest framework. The output of the rule is still a binary, but one whose
Mach-O type is `MH_BUNDLE` (a loadable bundle). Thus, the binary cannot be launched directly.
Instead, running `bazel test` on the target will launch a test runner script that copies it into an
`.xctest` bundle directory and then launches the `xctest` helper tool from Xcode, which uses
Objective-C runtime reflection to locate the tests.

On Linux, the output of a `swift_test` is a standard executable binary, because the implementation
of XCTest on that platform currently requires authors to explicitly list the tests that are present
and run them from their main program.

Test bundling on macOS can be disabled on a per-target basis, if desired. You may wish to do this if
you are not using XCTest, but rather a different test framework (or no framework at all) where the
pass/fail outcome is represented as a zero/non-zero exit code (as is the case with other Bazel test
rules like `cc_test`). To do so, disable the `"swift.bundled_xctests"` feature on the target:

```python
swift_test(
    name = "MyTests",
    srcs = [...],
    features = ["-swift.bundled_xctests"],
)
```

You can also disable this feature for all the tests in a package by applying it to your BUILD file's
`package()` declaration instead of the individual targets.

<a name="swift_test.attributes"></a>
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
<li><code>swift_c_module</code>, <code>swift_import</code> and <code>swift_library</code> (or anything propagating <code>SwiftInfo</code>)</li>
<li><code>cc_library</code> (or anything propagating <code>CcInfo</code>)</li>
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
        <p><code>List of strings; optional</code></p><p>Additional linker options that should be passed to <code>clang</code>. These strings are subject to
<code>$(location ...)</code> expansion.</p></td>
    </tr>
    <tr id="swift_test.malloc">
      <td><code>malloc</code></td>
      <td>
        <p><code><a href="https://docs.bazel.build/versions/master/build-ref.html#labels">Label</a>; optional; default is @bazel_tools//tools/cpp:malloc</code></p><p>Override the default dependency on <code>malloc</code>.</p>
<p>By default, Swift binaries are linked against <code>@bazel_tools//tools/cpp:malloc"</code>, which is an empty
library and the resulting binary will use libc's <code>malloc</code>. This label must refer to a <code>cc_library</code>
rule.</p></td>
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


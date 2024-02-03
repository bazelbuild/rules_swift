<!-- Generated with Stardoc, Do Not Edit! -->

BUILD rules to define Swift libraries and executable binaries.

This file is the public interface that users should import to use the Swift
rules. Do not import definitions from the `internal` subdirectory directly.

To use the Swift build rules in your BUILD files, load them from
`@build_bazel_rules_swift//swift:swift.bzl`.

For example:

```build
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
```
On this page:

  * [swift_binary](#swift_binary)
  * [swift_c_module](#swift_c_module)
  * [swift_compiler_plugin](#swift_compiler_plugin)
  * [universal_swift_compiler_plugin](#universal_swift_compiler_plugin)
  * [swift_feature_allowlist](#swift_feature_allowlist)
  * [swift_grpc_library](#swift_grpc_library)
  * [swift_import](#swift_import)
  * [swift_library](#swift_library)
  * [swift_library_group](#swift_library_group)
  * [swift_module_alias](#swift_module_alias)
  * [swift_package_configuration](#swift_package_configuration)
  * [swift_proto_library](#swift_proto_library)
  * [swift_test](#swift_test)

<a id="swift_binary"></a>

## swift_binary

<pre>
swift_binary(<a href="#swift_binary-name">name</a>, <a href="#swift_binary-deps">deps</a>, <a href="#swift_binary-srcs">srcs</a>, <a href="#swift_binary-data">data</a>, <a href="#swift_binary-copts">copts</a>, <a href="#swift_binary-defines">defines</a>, <a href="#swift_binary-linkopts">linkopts</a>, <a href="#swift_binary-malloc">malloc</a>, <a href="#swift_binary-module_name">module_name</a>, <a href="#swift_binary-package_name">package_name</a>,
             <a href="#swift_binary-plugins">plugins</a>, <a href="#swift_binary-stamp">stamp</a>, <a href="#swift_binary-swiftc_inputs">swiftc_inputs</a>)
</pre>

Compiles and links Swift code into an executable binary.

On Linux, this rule produces an executable binary for the desired target
architecture.

On Apple platforms, this rule produces a _single-architecture_ binary; it does
not produce fat binaries. As such, this rule is mainly useful for creating Swift
tools intended to run on the local build machine.

If you want to create a multi-architecture binary or a bundled application,
please use one of the platform-specific application rules in
[rules_apple](https://github.com/bazelbuild/rules_apple) instead of
`swift_binary`.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_binary-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_binary-deps"></a>deps |  A list of targets that are dependencies of the target being built, which will be linked into that target.<br><br>If the Swift toolchain supports implementation-only imports (`private_deps` on `swift_library`), then targets in `deps` are treated as regular (non-implementation-only) imports that are propagated both to their direct and indirect (transitive) dependents.<br><br>Allowed kinds of dependencies are:<br><br>*   `swift_c_module`, `swift_import` and `swift_library` (or anything     propagating `SwiftInfo`)<br><br>*   `cc_library` (or anything propagating `CcInfo`)<br><br>Additionally, on platforms that support Objective-C interop, `objc_library` targets (or anything propagating the `apple_common.Objc` provider) are allowed as dependencies. On platforms that do not support Objective-C interop (such as Linux), those dependencies will be **ignored.**   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_binary-srcs"></a>srcs |  A list of `.swift` source files that will be compiled into the library.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_binary-data"></a>data |  The list of files needed by this target at runtime.<br><br>Files and targets named in the `data` attribute will appear in the `*.runfiles` area of this target, if it has one. This may include data files needed by a binary or library, or other programs needed by it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_binary-copts"></a>copts |  Additional compiler options that should be passed to `swiftc`. These strings are subject to `$(location ...)` and ["Make" variable](https://docs.bazel.build/versions/master/be/make-variables.html) expansion.   | List of strings | optional |  `[]`  |
| <a id="swift_binary-defines"></a>defines |  A list of defines to add to the compilation command line.<br><br>Note that unlike C-family languages, Swift defines do not have values; they are simply identifiers that are either defined or undefined. So strings in this list should be simple identifiers, **not** `name=value` pairs.<br><br>Each string is prepended with `-D` and added to the command line. Unlike `copts`, these flags are added for the target and every target that depends on it, so use this attribute with caution. It is preferred that you add defines directly to `copts`, only using this feature in the rare case that a library needs to propagate a symbol up to those that depend on it.   | List of strings | optional |  `[]`  |
| <a id="swift_binary-linkopts"></a>linkopts |  Additional linker options that should be passed to `clang`. These strings are subject to `$(location ...)` expansion.   | List of strings | optional |  `[]`  |
| <a id="swift_binary-malloc"></a>malloc |  Override the default dependency on `malloc`.<br><br>By default, Swift binaries are linked against `@bazel_tools//tools/cpp:malloc"`, which is an empty library and the resulting binary will use libc's `malloc`. This label must refer to a `cc_library` rule.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@bazel_tools//tools/cpp:malloc"`  |
| <a id="swift_binary-module_name"></a>module_name |  The name of the Swift module being built.<br><br>If left unspecified, the module name will be computed based on the target's build label, by stripping the leading `//` and replacing `/`, `:`, and other non-identifier characters with underscores.   | String | optional |  `""`  |
| <a id="swift_binary-package_name"></a>package_name |  The semantic package of the Swift target being built. Targets with the same package_name can access APIs using the 'package' access control modifier in Swift 5.9+.   | String | optional |  `""`  |
| <a id="swift_binary-plugins"></a>plugins |  A list of `swift_compiler_plugin` targets that should be loaded by the compiler when compiling this module and any modules that directly depend on it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_binary-stamp"></a>stamp |  Enable or disable link stamping; that is, whether to encode build information into the binary. Possible values are:<br><br>* `stamp = 1`: Stamp the build information into the binary. Stamped binaries are   only rebuilt when their dependencies change. Use this if there are tests that   depend on the build information.<br><br>* `stamp = 0`: Always replace build information by constant values. This gives   good build result caching.<br><br>* `stamp = -1`: Embedding of build information is controlled by the   `--[no]stamp` flag.   | Integer | optional |  `-1`  |
| <a id="swift_binary-swiftc_inputs"></a>swiftc_inputs |  Additional files that are referenced using `$(location ...)` in attributes that support location expansion.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="swift_c_module"></a>

## swift_c_module

<pre>
swift_c_module(<a href="#swift_c_module-name">name</a>, <a href="#swift_c_module-deps">deps</a>, <a href="#swift_c_module-module_map">module_map</a>, <a href="#swift_c_module-module_name">module_name</a>, <a href="#swift_c_module-system_module_map">system_module_map</a>)
</pre>

Wraps one or more C targets in a new module map that allows it to be imported
into Swift to access its C interfaces.

The `cc_library` rule in Bazel does not produce module maps that are compatible
with Swift. In order to make interop between Swift and C possible, users have
one of two options:

1.  **Use an auto-generated module map.** In this case, the `swift_c_module`
    rule is not needed. If a `cc_library` is a direct dependency of a
    `swift_{binary,library,test}` target, a module map will be automatically
    generated for it and the module's name will be derived from the Bazel target
    label (in the same fashion that module names for Swift targets are derived).
    The module name can be overridden by setting the `swift_module` tag on the
    `cc_library`; e.g., `tags = ["swift_module=MyModule"]`.

2.  **Use a custom module map.** For finer control over the headers that are
    exported by the module, use the `swift_c_module` rule to provide a custom
    module map that specifies the name of the module, its headers, and any other
    module information. The `cc_library` targets that contain the headers that
    you wish to expose to Swift should be listed in the `deps` of your
    `swift_c_module` (and by listing multiple targets, you can export multiple
    libraries under a single module if desired). Then, your
    `swift_{binary,library,test}` targets should depend on the `swift_c_module`
    target, not on the underlying `cc_library` target(s).

NOTE: Swift at this time does not support interop directly with C++. Any headers
referenced by a module map that is imported into Swift must have only C features
visible, often by using preprocessor conditions like `#if __cplusplus` to hide
any C++ declarations.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_c_module-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_c_module-deps"></a>deps |  A list of C targets (or anything propagating `CcInfo`) that are dependencies of this target and whose headers may be referenced by the module map.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_c_module-module_map"></a>module_map |  The module map file that should be loaded to import the C library dependency into Swift. This is mutally exclusive with `system_module_map`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="swift_c_module-module_name"></a>module_name |  The name of the top-level module in the module map that this target represents.<br><br>A single `module.modulemap` file can define multiple top-level modules. When building with implicit modules, the presence of that module map allows any of the modules defined in it to be imported. When building explicit modules, however, there is a one-to-one correspondence between top-level modules and BUILD targets and the module name must be known without reading the module map file, so it must be provided directly. Therefore, one may have multiple `swift_c_module` targets that reference the same `module.modulemap` file but with different module names and headers.   | String | required |  |
| <a id="swift_c_module-system_module_map"></a>system_module_map |  The path to a system framework module map. This is mutually exclusive with `module_map`.<br><br>Variables `__BAZEL_XCODE_SDKROOT__` and `__BAZEL_XCODE_DEVELOPER_DIR__` will be substitued appropriately for, i.e. `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk` and `/Applications/Xcode.app/Contents/Developer` respectively.   | String | optional |  `""`  |


<a id="swift_compiler_plugin"></a>

## swift_compiler_plugin

<pre>
swift_compiler_plugin(<a href="#swift_compiler_plugin-name">name</a>, <a href="#swift_compiler_plugin-deps">deps</a>, <a href="#swift_compiler_plugin-srcs">srcs</a>, <a href="#swift_compiler_plugin-data">data</a>, <a href="#swift_compiler_plugin-copts">copts</a>, <a href="#swift_compiler_plugin-defines">defines</a>, <a href="#swift_compiler_plugin-linkopts">linkopts</a>, <a href="#swift_compiler_plugin-malloc">malloc</a>, <a href="#swift_compiler_plugin-module_name">module_name</a>,
                      <a href="#swift_compiler_plugin-package_name">package_name</a>, <a href="#swift_compiler_plugin-plugins">plugins</a>, <a href="#swift_compiler_plugin-stamp">stamp</a>, <a href="#swift_compiler_plugin-swiftc_inputs">swiftc_inputs</a>)
</pre>

Compiles and links a Swift compiler plugin (for example, a macro).

A compiler plugin is a standalone executable that minimally implements the
`CompilerPlugin` protocol from the `SwiftCompilerPlugin` module in swift-syntax.
As of the time of this writing (Xcode 15.0), a compiler plugin can contain one
or more macros, which can be associated with other Swift targets to perform
syntax-tree-based expansions.

When a `swift_compiler_plugin` target is listed in the `plugins` attribute of a
`swift_library`, it will be loaded by that library and any targets that directly
depend on it. (The `plugins` attribute also exists on `swift_binary`,
`swift_test`, and `swift_compiler_plugin` itself, to support plugins that are
only used within those targets.)

Compiler plugins also support being built as a library so that they can be
tested. The `swift_test` rule can contain `swift_compiler_plugin` targets in its
`deps`, and the plugin's module can be imported by the test's sources so that
unit tests can be written against the plugin.

Example:

```bzl
# The actual macro code, using SwiftSyntax
swift_compiler_plugin(
    name = "Macros",
    srcs = glob(["Macros/*.swift"]),
    deps = [
        "@SwiftSyntax",
        "@SwiftSyntax//:SwiftCompilerPlugin",
        "@SwiftSyntax//:SwiftSyntaxMacros",
    ],
)

# A target testing the macro itself
swift_test(
    name = "MacrosTests",
    srcs = glob(["MacrosTests/*.swift"]),
    deps = [
        ":Macros",
        "@SwiftSyntax//:SwiftSyntaxMacrosTestSupport",
    ],
)

# The library that defines the macro hook for use in your project
swift_library(
    name = "MacroLibrary",
    srcs = glob(["MacroLibrary/*.swift"]),
    plugins = [":Macros"],
)

# A consumer of the macro library. This doesn't have to be separate from the
# MacroLibrary depending on what makes sense for your project's organization
swift_library(
    name = "MacroConsumer",
    srcs = glob(["Sources/*.swift"]),
    deps = [":MacroLibrary"],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_compiler_plugin-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_compiler_plugin-deps"></a>deps |  A list of targets that are dependencies of the target being built, which will be linked into that target.<br><br>If the Swift toolchain supports implementation-only imports (`private_deps` on `swift_library`), then targets in `deps` are treated as regular (non-implementation-only) imports that are propagated both to their direct and indirect (transitive) dependents.<br><br>Allowed kinds of dependencies are:<br><br>*   `swift_c_module`, `swift_import` and `swift_library` (or anything     propagating `SwiftInfo`)<br><br>*   `cc_library` (or anything propagating `CcInfo`)<br><br>Additionally, on platforms that support Objective-C interop, `objc_library` targets (or anything propagating the `apple_common.Objc` provider) are allowed as dependencies. On platforms that do not support Objective-C interop (such as Linux), those dependencies will be **ignored.**   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_compiler_plugin-srcs"></a>srcs |  A list of `.swift` source files that will be compiled into the library.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_compiler_plugin-data"></a>data |  The list of files needed by this target at runtime.<br><br>Files and targets named in the `data` attribute will appear in the `*.runfiles` area of this target, if it has one. This may include data files needed by a binary or library, or other programs needed by it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_compiler_plugin-copts"></a>copts |  Additional compiler options that should be passed to `swiftc`. These strings are subject to `$(location ...)` and ["Make" variable](https://docs.bazel.build/versions/master/be/make-variables.html) expansion.   | List of strings | optional |  `[]`  |
| <a id="swift_compiler_plugin-defines"></a>defines |  A list of defines to add to the compilation command line.<br><br>Note that unlike C-family languages, Swift defines do not have values; they are simply identifiers that are either defined or undefined. So strings in this list should be simple identifiers, **not** `name=value` pairs.<br><br>Each string is prepended with `-D` and added to the command line. Unlike `copts`, these flags are added for the target and every target that depends on it, so use this attribute with caution. It is preferred that you add defines directly to `copts`, only using this feature in the rare case that a library needs to propagate a symbol up to those that depend on it.   | List of strings | optional |  `[]`  |
| <a id="swift_compiler_plugin-linkopts"></a>linkopts |  Additional linker options that should be passed to `clang`. These strings are subject to `$(location ...)` expansion.   | List of strings | optional |  `[]`  |
| <a id="swift_compiler_plugin-malloc"></a>malloc |  Override the default dependency on `malloc`.<br><br>By default, Swift binaries are linked against `@bazel_tools//tools/cpp:malloc"`, which is an empty library and the resulting binary will use libc's `malloc`. This label must refer to a `cc_library` rule.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@bazel_tools//tools/cpp:malloc"`  |
| <a id="swift_compiler_plugin-module_name"></a>module_name |  The name of the Swift module being built.<br><br>If left unspecified, the module name will be computed based on the target's build label, by stripping the leading `//` and replacing `/`, `:`, and other non-identifier characters with underscores.   | String | optional |  `""`  |
| <a id="swift_compiler_plugin-package_name"></a>package_name |  The semantic package of the Swift target being built. Targets with the same package_name can access APIs using the 'package' access control modifier in Swift 5.9+.   | String | optional |  `""`  |
| <a id="swift_compiler_plugin-plugins"></a>plugins |  A list of `swift_compiler_plugin` targets that should be loaded by the compiler when compiling this module and any modules that directly depend on it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_compiler_plugin-stamp"></a>stamp |  Enable or disable link stamping; that is, whether to encode build information into the binary. Possible values are:<br><br>* `stamp = 1`: Stamp the build information into the binary. Stamped binaries are   only rebuilt when their dependencies change. Use this if there are tests that   depend on the build information.<br><br>* `stamp = 0`: Always replace build information by constant values. This gives   good build result caching.<br><br>* `stamp = -1`: Embedding of build information is controlled by the   `--[no]stamp` flag.   | Integer | optional |  `0`  |
| <a id="swift_compiler_plugin-swiftc_inputs"></a>swiftc_inputs |  Additional files that are referenced using `$(location ...)` in attributes that support location expansion.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="swift_feature_allowlist"></a>

## swift_feature_allowlist

<pre>
swift_feature_allowlist(<a href="#swift_feature_allowlist-name">name</a>, <a href="#swift_feature_allowlist-managed_features">managed_features</a>, <a href="#swift_feature_allowlist-packages">packages</a>)
</pre>

Limits the ability to request or disable certain features to a set of packages
(and possibly subpackages) in the workspace.

A Swift toolchain target can reference any number (zero or more) of
`swift_feature_allowlist` targets. The features managed by these allowlists may
overlap. For some package _P_, a feature is allowed to be used by targets in
that package if _P_ matches the `packages` patterns in *all* of the allowlists
that manage that feature.

A feature that is not managed by any allowlist is allowed to be used by any
package.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_feature_allowlist-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_feature_allowlist-managed_features"></a>managed_features |  A list of feature strings that are permitted to be specified by the targets in the packages matched by the `packages` attribute. This list may include both feature names and/or negations (a name with a leading `-`); a regular feature name means that the targets in the matching packages may explicitly request that the feature be enabled, and a negated feature means that the target may explicitly request that the feature be disabled.<br><br>For example, `managed_features = ["foo", "-bar"]` means that targets in the allowlist's packages may request that feature `"foo"` be enabled and that feature `"bar"` be disabled.   | List of strings | optional |  `[]`  |
| <a id="swift_feature_allowlist-packages"></a>packages |  A list of strings representing packages (possibly recursive) whose targets are allowed to enable/disable the features in `managed_features`. Each package pattern is written in the syntax used by the `package_group` function:<br><br>*   `//foo/bar`: Targets in the package `//foo/bar` but not in subpackages. *   `//foo/bar/...`: Targets in the package `//foo/bar` and any of its     subpackages. *   A leading `-` excludes packages that would otherwise have been included by     the patterns in the list.<br><br>Exclusions always take priority over inclusions; order in the list is irrelevant.   | List of strings | required |  |


<a id="swift_grpc_library"></a>

## swift_grpc_library

<pre>
swift_grpc_library(<a href="#swift_grpc_library-name">name</a>, <a href="#swift_grpc_library-deps">deps</a>, <a href="#swift_grpc_library-srcs">srcs</a>, <a href="#swift_grpc_library-flavor">flavor</a>)
</pre>

Generates a Swift library from gRPC services defined in protocol buffer sources.

There should be one `swift_grpc_library` for any `proto_library` that defines
services. A target based on this rule can be used as a dependency anywhere that
a `swift_library` can be used.

We recommend that `swift_grpc_library` targets be located in the same package as
the `proto_library` and `swift_proto_library` targets they depend on. For more
best practices around the use of Swift protocol buffer build rules, see the
documentation for `swift_proto_library`.

#### Defining Build Targets for Services

Note that `swift_grpc_library` only generates the gRPC service interfaces (the
`service` definitions) from the `.proto` files. Any messages defined in the same
`.proto` file must be generated using a `swift_proto_library` target. Thus, the
typical structure of a Swift gRPC library is similar to the following:

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

    # The `srcs` attribute points to the `proto_library` containing the service
    # definitions...
    srcs = [":my_protos"],

    # ...the `flavor` attribute specifies the kind of definitions to generate...
    flavor = "client",

    # ...and the `deps` attribute points to the `swift_proto_library` that was
    # generated from the same `proto_library` and which contains the messages
    # used by those services.
    deps = [":my_protos_swift"],
)

# Generate test stubs from swift services.
swift_grpc_library(
    name = "my_protos_client_stubs_swift",

    # The `srcs` attribute points to the `proto_library` containing the service
    # definitions...
    srcs = [":my_protos"],

    # ...the `flavor` attribute specifies the kind of definitions to generate...
    flavor = "client_stubs",

    # ...and the `deps` attribute points to the `swift_grpc_library` that was
    # generated from the same `proto_library` and which contains the service
    # implementation.
    deps = [":my_protos_client_services_swift"],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_grpc_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_grpc_library-deps"></a>deps |  Exactly one `swift_proto_library` or `swift_grpc_library` target that contains the Swift protos used by the services being generated. Test stubs should depend on the `swift_grpc_library` implementing the service.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_grpc_library-srcs"></a>srcs |  Exactly one `proto_library` target that defines the services being generated.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_grpc_library-flavor"></a>flavor |  The kind of definitions that should be generated:<br><br>*   `"client"` to generate client definitions.<br><br>*   `"client_stubs"` to generate client test stubs.<br><br>*   `"server"` to generate server definitions.   | String | required |  |


<a id="swift_import"></a>

## swift_import

<pre>
swift_import(<a href="#swift_import-name">name</a>, <a href="#swift_import-deps">deps</a>, <a href="#swift_import-data">data</a>, <a href="#swift_import-archives">archives</a>, <a href="#swift_import-module_name">module_name</a>, <a href="#swift_import-swiftdoc">swiftdoc</a>, <a href="#swift_import-swiftinterface">swiftinterface</a>, <a href="#swift_import-swiftmodule">swiftmodule</a>)
</pre>

Allows for the use of Swift textual module interfaces and/or precompiled Swift modules as dependencies in other
`swift_library` and `swift_binary` targets.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_import-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_import-deps"></a>deps |  A list of targets that are dependencies of the target being built, which will be linked into that target.<br><br>If the Swift toolchain supports implementation-only imports (`private_deps` on `swift_library`), then targets in `deps` are treated as regular (non-implementation-only) imports that are propagated both to their direct and indirect (transitive) dependents.<br><br>Allowed kinds of dependencies are:<br><br>*   `swift_c_module`, `swift_import` and `swift_library` (or anything     propagating `SwiftInfo`)<br><br>*   `cc_library` (or anything propagating `CcInfo`)<br><br>Additionally, on platforms that support Objective-C interop, `objc_library` targets (or anything propagating the `apple_common.Objc` provider) are allowed as dependencies. On platforms that do not support Objective-C interop (such as Linux), those dependencies will be **ignored.**   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_import-data"></a>data |  The list of files needed by this target at runtime.<br><br>Files and targets named in the `data` attribute will appear in the `*.runfiles` area of this target, if it has one. This may include data files needed by a binary or library, or other programs needed by it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_import-archives"></a>archives |  The list of `.a` files provided to Swift targets that depend on this target.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_import-module_name"></a>module_name |  The name of the module represented by this target.   | String | required |  |
| <a id="swift_import-swiftdoc"></a>swiftdoc |  The `.swiftdoc` file provided to Swift targets that depend on this target.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="swift_import-swiftinterface"></a>swiftinterface |  The `.swiftinterface` file that defines the module interface for this target.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="swift_import-swiftmodule"></a>swiftmodule |  The `.swiftmodule` file provided to Swift targets that depend on this target.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


<a id="swift_library"></a>

## swift_library

<pre>
swift_library(<a href="#swift_library-name">name</a>, <a href="#swift_library-deps">deps</a>, <a href="#swift_library-srcs">srcs</a>, <a href="#swift_library-data">data</a>, <a href="#swift_library-always_include_developer_search_paths">always_include_developer_search_paths</a>, <a href="#swift_library-alwayslink">alwayslink</a>, <a href="#swift_library-copts">copts</a>,
              <a href="#swift_library-defines">defines</a>, <a href="#swift_library-generated_header_name">generated_header_name</a>, <a href="#swift_library-generates_header">generates_header</a>, <a href="#swift_library-linkopts">linkopts</a>, <a href="#swift_library-linkstatic">linkstatic</a>, <a href="#swift_library-module_name">module_name</a>,
              <a href="#swift_library-package_name">package_name</a>, <a href="#swift_library-plugins">plugins</a>, <a href="#swift_library-private_deps">private_deps</a>, <a href="#swift_library-swiftc_inputs">swiftc_inputs</a>)
</pre>

Compiles and links Swift code into a static library and Swift module.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_library-deps"></a>deps |  A list of targets that are dependencies of the target being built, which will be linked into that target.<br><br>If the Swift toolchain supports implementation-only imports (`private_deps` on `swift_library`), then targets in `deps` are treated as regular (non-implementation-only) imports that are propagated both to their direct and indirect (transitive) dependents.<br><br>Allowed kinds of dependencies are:<br><br>*   `swift_c_module`, `swift_import` and `swift_library` (or anything     propagating `SwiftInfo`)<br><br>*   `cc_library` (or anything propagating `CcInfo`)<br><br>Additionally, on platforms that support Objective-C interop, `objc_library` targets (or anything propagating the `apple_common.Objc` provider) are allowed as dependencies. On platforms that do not support Objective-C interop (such as Linux), those dependencies will be **ignored.**   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_library-srcs"></a>srcs |  A list of `.swift` source files that will be compiled into the library.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="swift_library-data"></a>data |  The list of files needed by this target at runtime.<br><br>Files and targets named in the `data` attribute will appear in the `*.runfiles` area of this target, if it has one. This may include data files needed by a binary or library, or other programs needed by it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_library-always_include_developer_search_paths"></a>always_include_developer_search_paths |  If `True`, the developer framework search paths will be added to the compilation command. This enables a Swift module to access `XCTest` without having to mark the target as `testonly = True`.   | Boolean | optional |  `False`  |
| <a id="swift_library-alwayslink"></a>alwayslink |  If true, any binary that depends (directly or indirectly) on this Swift module will link in all the object files for the files listed in `srcs`, even if some contain no symbols referenced by the binary. This is useful if your code isn't explicitly called by code in the binary; for example, if you rely on runtime checks for protocol conformances added in extensions in the library but do not directly reference any other symbols in the object file that adds that conformance.   | Boolean | optional |  `False`  |
| <a id="swift_library-copts"></a>copts |  Additional compiler options that should be passed to `swiftc`. These strings are subject to `$(location ...)` and ["Make" variable](https://docs.bazel.build/versions/master/be/make-variables.html) expansion.   | List of strings | optional |  `[]`  |
| <a id="swift_library-defines"></a>defines |  A list of defines to add to the compilation command line.<br><br>Note that unlike C-family languages, Swift defines do not have values; they are simply identifiers that are either defined or undefined. So strings in this list should be simple identifiers, **not** `name=value` pairs.<br><br>Each string is prepended with `-D` and added to the command line. Unlike `copts`, these flags are added for the target and every target that depends on it, so use this attribute with caution. It is preferred that you add defines directly to `copts`, only using this feature in the rare case that a library needs to propagate a symbol up to those that depend on it.   | List of strings | optional |  `[]`  |
| <a id="swift_library-generated_header_name"></a>generated_header_name |  The name of the generated Objective-C interface header. This name must end with a `.h` extension and cannot contain any path separators.<br><br>If this attribute is not specified, then the default behavior is to name the header `${target_name}-Swift.h`.<br><br>This attribute is ignored if the toolchain does not support generating headers.   | String | optional |  `""`  |
| <a id="swift_library-generates_header"></a>generates_header |  If True, an Objective-C header will be generated for this target, in the same build package where the target is defined. By default, the name of the header is `${target_name}-Swift.h`; this can be changed using the `generated_header_name` attribute.<br><br>Targets should only set this attribute to True if they export Objective-C APIs. A header generated for a target that does not export Objective-C APIs will be effectively empty (except for a large amount of prologue and epilogue code) and this is generally wasteful because the extra file needs to be propagated in the build graph and, when explicit modules are enabled, extra actions must be executed to compile the Objective-C module for the generated header.   | Boolean | optional |  `False`  |
| <a id="swift_library-linkopts"></a>linkopts |  Additional linker options that should be passed to the linker for the binary that depends on this target. These strings are subject to `$(location ...)` and ["Make" variable](https://docs.bazel.build/versions/master/be/make-variables.html) expansion.   | List of strings | optional |  `[]`  |
| <a id="swift_library-linkstatic"></a>linkstatic |  If True, the Swift module will be built for static linking.  This will make all interfaces internal to the module that is being linked against and will inform the consuming module that the objects will be locally available (which may potentially avoid a PLT relocation).  Set to `False` to build a `.so` or `.dll`.   | Boolean | optional |  `True`  |
| <a id="swift_library-module_name"></a>module_name |  The name of the Swift module being built.<br><br>If left unspecified, the module name will be computed based on the target's build label, by stripping the leading `//` and replacing `/`, `:`, and other non-identifier characters with underscores.   | String | optional |  `""`  |
| <a id="swift_library-package_name"></a>package_name |  The semantic package of the Swift target being built. Targets with the same package_name can access APIs using the 'package' access control modifier in Swift 5.9+.   | String | optional |  `""`  |
| <a id="swift_library-plugins"></a>plugins |  A list of `swift_compiler_plugin` targets that should be loaded by the compiler when compiling this module and any modules that directly depend on it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_library-private_deps"></a>private_deps |  A list of targets that are implementation-only dependencies of the target being built. Libraries/linker flags from these dependencies will be propagated to dependent for linking, but artifacts/flags required for compilation (such as .swiftmodule files, C headers, and search paths) will not be propagated.<br><br>Allowed kinds of dependencies are:<br><br>*   `swift_c_module`, `swift_import` and `swift_library` (or anything     propagating `SwiftInfo`)<br><br>*   `cc_library` (or anything propagating `CcInfo`)<br><br>Additionally, on platforms that support Objective-C interop, `objc_library` targets (or anything propagating the `apple_common.Objc` provider) are allowed as dependencies. On platforms that do not support Objective-C interop (such as Linux), those dependencies will be **ignored.**   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_library-swiftc_inputs"></a>swiftc_inputs |  Additional files that are referenced using `$(location ...)` in attributes that support location expansion.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="swift_library_group"></a>

## swift_library_group

<pre>
swift_library_group(<a href="#swift_library_group-name">name</a>, <a href="#swift_library_group-deps">deps</a>)
</pre>

Groups Swift compatible libraries (e.g. `swift_library` and `objc_library`).
The target can be used anywhere a `swift_library` can be used. It behaves
similar to source-less `{cc,obj}_library` targets.

Unlike `swift_module_alias`, a new module isn't created for this target, you
need to import the grouped libraries directly.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_library_group-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_library_group-deps"></a>deps |  A list of targets that should be included in the group.<br><br>Allowed kinds of dependencies are:<br><br>*   `swift_c_module`, `swift_import` and `swift_library` (or anything     propagating `SwiftInfo`)<br><br>*   `cc_library` (or anything propagating `CcInfo`)<br><br>Additionally, on platforms that support Objective-C interop, `objc_library` targets (or anything propagating the `apple_common.Objc` provider) are allowed as dependencies. On platforms that do not support Objective-C interop (such as Linux), those dependencies will be **ignored.**   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="swift_module_alias"></a>

## swift_module_alias

<pre>
swift_module_alias(<a href="#swift_module_alias-name">name</a>, <a href="#swift_module_alias-deps">deps</a>, <a href="#swift_module_alias-module_name">module_name</a>)
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

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_module_alias-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_module_alias-deps"></a>deps |  A list of targets that are dependencies of the target being built, which will be linked into that target. Allowed kinds are `swift_import` and `swift_library` (or anything else propagating `SwiftInfo`).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_module_alias-module_name"></a>module_name |  The name of the Swift module being built.<br><br>If left unspecified, the module name will be computed based on the target's build label, by stripping the leading `//` and replacing `/`, `:`, and other non-identifier characters with underscores.   | String | optional |  `""`  |


<a id="swift_package_configuration"></a>

## swift_package_configuration

<pre>
swift_package_configuration(<a href="#swift_package_configuration-name">name</a>, <a href="#swift_package_configuration-configured_features">configured_features</a>, <a href="#swift_package_configuration-packages">packages</a>)
</pre>

A compilation configuration to apply to the Swift targets in a set of packages.

A Swift toolchain target can reference any number (zero or more) of
`swift_package_configuration` targets. When the compilation action for a target
is being configured, those package configurations will be applied if the
target's label is included by the package specifications in the configuration.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_package_configuration-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_package_configuration-configured_features"></a>configured_features |  A list of feature strings that will be applied by default to targets in the packages matched by the `packages` attribute, as if they had been specified by the `package(features = ...)` rule in the BUILD file.<br><br>This list may include both feature names and/or negations (a name with a leading `-`); a regular feature name means that the targets in the matching packages will have the feature enabled, and a negated feature means that the target will have the feature disabled.<br><br>For example, `configured_features = ["foo", "-bar"]` means that targets in the configuration's packages will have the feature `"foo"` enabled by default and the feature `"bar"` disabled by default.   | List of strings | optional |  `[]`  |
| <a id="swift_package_configuration-packages"></a>packages |  A list of strings representing packages (possibly recursive) whose targets will have this package configuration applied. Each package pattern is written in the syntax used by the `package_group` function:<br><br>*   `//foo/bar`: Targets in the package `//foo/bar` but not in subpackages. *   `//foo/bar/...`: Targets in the package `//foo/bar` and any of its     subpackages. *   A leading `-` excludes packages that would otherwise have been included by     the patterns in the list.<br><br>Exclusions always take priority over inclusions; order in the list is irrelevant.   | List of strings | required |  |


<a id="swift_proto_library"></a>

## swift_proto_library

<pre>
swift_proto_library(<a href="#swift_proto_library-name">name</a>, <a href="#swift_proto_library-deps">deps</a>)
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

Note that the module name of the Swift library produced by this rule (if any) is
based on the name of the `proto_library` target, *not* the name of the
`swift_proto_library` target. In other words, if the following BUILD file were
located in `//my/pkg`, the target would create a Swift module named
`my_pkg_foo`:

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

Because the Swift modules are generated from an aspect that is applied to the
`proto_library` targets, the module name and other compilation flags for the
resulting Swift modules cannot be changed.

#### Tip: Where to locate `swift_proto_library` targets

Convention is to put the `swift_proto_library` in the same `BUILD` file as the
`proto_library` it is generating for (just like all the other
`LANG_proto_library` rules). This lets anyone needing the protos in Swift share
the single rule as well as making it easier to realize what proto files are in
use in what contexts.

This is not a requirement, however, as it may not be possible for Bazel
workspaces that create `swift_proto_library` targets that depend on
`proto_library` targets from different repositories.

#### Tip: Avoid `import` only `.proto` files

Avoid creating a `.proto` file that just contains `import` directives of all the
other `.proto` files you need. While this does _group_ the protos into this new
target, it comes with some high costs. This causes the proto compiler to parse
all those files and invoke the generator for an otherwise empty source file.
That empty source file then has to get compiled, but it will have dependencies
on the full deps chain of the imports (recursively). The Swift compiler must
load all of these module dependencies, which can be fairly slow if there are
many of them, so this method of grouping via a `.proto` file actually ends up
creating build steps that slow down the build.

#### Tip: Resolving unused import warnings

If you see warnings like the following during your build:

```
path/file.proto: warning: Import other/path/file.proto but not used.
```

The proto compiler is letting you know that you have an `import` statement
loading a file from which nothing is used, so it is wasted work. The `import`
can be removed (in this case, `import other/path/file.proto` could be removed
from `path/file.proto`). These warnings can also mean that the `proto_library`
has `deps` that aren't needed. Removing those along with the `import`
statement(s) will speed up downstream Swift compilation actions, because it
prevents unused modules from being loaded by `swiftc`.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_proto_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_proto_library-deps"></a>deps |  Exactly one `proto_library` target (or any target that propagates a `proto` provider) from which the Swift library should be generated.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="swift_test"></a>

## swift_test

<pre>
swift_test(<a href="#swift_test-name">name</a>, <a href="#swift_test-deps">deps</a>, <a href="#swift_test-srcs">srcs</a>, <a href="#swift_test-data">data</a>, <a href="#swift_test-copts">copts</a>, <a href="#swift_test-defines">defines</a>, <a href="#swift_test-env">env</a>, <a href="#swift_test-linkopts">linkopts</a>, <a href="#swift_test-malloc">malloc</a>, <a href="#swift_test-module_name">module_name</a>, <a href="#swift_test-package_name">package_name</a>,
           <a href="#swift_test-plugins">plugins</a>, <a href="#swift_test-stamp">stamp</a>, <a href="#swift_test-swiftc_inputs">swiftc_inputs</a>)
</pre>

Compiles and links Swift code into an executable test target.

The behavior of `swift_test` differs slightly for macOS targets, in order to
provide seamless integration with Apple's XCTest framework. The output of the
rule is still a binary, but one whose Mach-O type is `MH_BUNDLE` (a loadable
bundle). Thus, the binary cannot be launched directly. Instead, running
`bazel test` on the target will launch a test runner script that copies it into
an `.xctest` bundle directory and then launches the `xctest` helper tool from
Xcode, which uses Objective-C runtime reflection to locate the tests.

On Linux, the output of a `swift_test` is a standard executable binary, because
the implementation of XCTest on that platform currently requires authors to
explicitly list the tests that are present and run them from their main program.

Test bundling on macOS can be disabled on a per-target basis, if desired. You
may wish to do this if you are not using XCTest, but rather a different test
framework (or no framework at all) where the pass/fail outcome is represented as
a zero/non-zero exit code (as is the case with other Bazel test rules like
`cc_test`). To do so, disable the `"swift.bundled_xctests"` feature on the
target:

```python
swift_test(
    name = "MyTests",
    srcs = [...],
    features = ["-swift.bundled_xctests"],
)
```

You can also disable this feature for all the tests in a package by applying it
to your BUILD file's `package()` declaration instead of the individual targets.

If integrating with Xcode, the relative paths in test binaries can prevent the
Issue navigator from working for test failures. To work around this, you can
have the paths made absolute via swizzling by enabling the
`"apple.swizzle_absolute_xcttestsourcelocation"` feature. You'll also need to
set the `BUILD_WORKSPACE_DIRECTORY` environment variable in your scheme to the
root of your workspace (i.e. `$(SRCROOT)`).

A subset of tests for a given target can be executed via the `--test_filter` parameter:

```
bazel test //:Tests --test_filter=TestModuleName.TestClassName/testMethodName
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="swift_test-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="swift_test-deps"></a>deps |  A list of targets that are dependencies of the target being built, which will be linked into that target.<br><br>If the Swift toolchain supports implementation-only imports (`private_deps` on `swift_library`), then targets in `deps` are treated as regular (non-implementation-only) imports that are propagated both to their direct and indirect (transitive) dependents.<br><br>Allowed kinds of dependencies are:<br><br>*   `swift_c_module`, `swift_import` and `swift_library` (or anything     propagating `SwiftInfo`)<br><br>*   `cc_library` (or anything propagating `CcInfo`)<br><br>Additionally, on platforms that support Objective-C interop, `objc_library` targets (or anything propagating the `apple_common.Objc` provider) are allowed as dependencies. On platforms that do not support Objective-C interop (such as Linux), those dependencies will be **ignored.**   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_test-srcs"></a>srcs |  A list of `.swift` source files that will be compiled into the library.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_test-data"></a>data |  The list of files needed by this target at runtime.<br><br>Files and targets named in the `data` attribute will appear in the `*.runfiles` area of this target, if it has one. This may include data files needed by a binary or library, or other programs needed by it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_test-copts"></a>copts |  Additional compiler options that should be passed to `swiftc`. These strings are subject to `$(location ...)` and ["Make" variable](https://docs.bazel.build/versions/master/be/make-variables.html) expansion.   | List of strings | optional |  `[]`  |
| <a id="swift_test-defines"></a>defines |  A list of defines to add to the compilation command line.<br><br>Note that unlike C-family languages, Swift defines do not have values; they are simply identifiers that are either defined or undefined. So strings in this list should be simple identifiers, **not** `name=value` pairs.<br><br>Each string is prepended with `-D` and added to the command line. Unlike `copts`, these flags are added for the target and every target that depends on it, so use this attribute with caution. It is preferred that you add defines directly to `copts`, only using this feature in the rare case that a library needs to propagate a symbol up to those that depend on it.   | List of strings | optional |  `[]`  |
| <a id="swift_test-env"></a>env |  Dictionary of environment variables that should be set during the test execution.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="swift_test-linkopts"></a>linkopts |  Additional linker options that should be passed to `clang`. These strings are subject to `$(location ...)` expansion.   | List of strings | optional |  `[]`  |
| <a id="swift_test-malloc"></a>malloc |  Override the default dependency on `malloc`.<br><br>By default, Swift binaries are linked against `@bazel_tools//tools/cpp:malloc"`, which is an empty library and the resulting binary will use libc's `malloc`. This label must refer to a `cc_library` rule.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@bazel_tools//tools/cpp:malloc"`  |
| <a id="swift_test-module_name"></a>module_name |  The name of the Swift module being built.<br><br>If left unspecified, the module name will be computed based on the target's build label, by stripping the leading `//` and replacing `/`, `:`, and other non-identifier characters with underscores.   | String | optional |  `""`  |
| <a id="swift_test-package_name"></a>package_name |  The semantic package of the Swift target being built. Targets with the same package_name can access APIs using the 'package' access control modifier in Swift 5.9+.   | String | optional |  `""`  |
| <a id="swift_test-plugins"></a>plugins |  A list of `swift_compiler_plugin` targets that should be loaded by the compiler when compiling this module and any modules that directly depend on it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="swift_test-stamp"></a>stamp |  Enable or disable link stamping; that is, whether to encode build information into the binary. Possible values are:<br><br>* `stamp = 1`: Stamp the build information into the binary. Stamped binaries are   only rebuilt when their dependencies change. Use this if there are tests that   depend on the build information.<br><br>* `stamp = 0`: Always replace build information by constant values. This gives   good build result caching.<br><br>* `stamp = -1`: Embedding of build information is controlled by the   `--[no]stamp` flag.   | Integer | optional |  `0`  |
| <a id="swift_test-swiftc_inputs"></a>swiftc_inputs |  Additional files that are referenced using `$(location ...)` in attributes that support location expansion.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="universal_swift_compiler_plugin"></a>

## universal_swift_compiler_plugin

<pre>
universal_swift_compiler_plugin(<a href="#universal_swift_compiler_plugin-name">name</a>, <a href="#universal_swift_compiler_plugin-plugin">plugin</a>)
</pre>

Wraps an existing `swift_compiler_plugin` target to produce a universal binary.

This is useful to allow sharing of caches between Intel and Apple Silicon Macs
at the cost of building everything twice.

Example:

```bzl
# The actual macro code, using SwiftSyntax, as usual.
swift_compiler_plugin(
    name = "Macros",
    srcs = glob(["Macros/*.swift"]),
    deps = [
        "@SwiftSyntax",
        "@SwiftSyntax//:SwiftCompilerPlugin",
        "@SwiftSyntax//:SwiftSyntaxMacros",
    ],
)

# Wrap your compiler plugin in this universal shim.
universal_swift_compiler_plugin(
    name = "Macros.universal",
    plugin = ":Macros",
)

# The library that defines the macro hook for use in your project, this
# references the universal_swift_compiler_plugin.
swift_library(
    name = "MacroLibrary",
    srcs = glob(["MacroLibrary/*.swift"]),
    plugins = [":Macros.universal"],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="universal_swift_compiler_plugin-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="universal_swift_compiler_plugin-plugin"></a>plugin |  Target to generate a 'fat' binary from.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |



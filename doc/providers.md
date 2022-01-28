<!-- Generated with Stardoc, Do Not Edit! -->

The providers described below are propagated and required by various Swift
build rules. Clients interested in writing custom rules that interface
with the rules in this package should use these providers to communicate
with the Swift build rules as needed.

On this page:

  * [SwiftInfo](#SwiftInfo)
  * [SwiftToolchainInfo](#SwiftToolchainInfo)
  * [SwiftProtoInfo](#SwiftProtoInfo)
  * [SwiftUsageInfo](#SwiftUsageInfo)

<a id="#SwiftInfo"></a>

## SwiftInfo

<pre>
SwiftInfo(<a href="#SwiftInfo-direct_modules">direct_modules</a>, <a href="#SwiftInfo-transitive_modules">transitive_modules</a>)
</pre>

Contains information about the compiled artifacts of a Swift module.

This provider contains a large number of fields and many custom rules may not
need to set all of them. Instead of constructing a `SwiftInfo` provider
directly, consider using the `swift_common.create_swift_info` function, which
has reasonable defaults for any fields not explicitly set.


**FIELDS**


| Name  | Description |
| :------------- | :------------- |
| <a id="SwiftInfo-direct_modules"></a>direct_modules |  <code>List</code> of values returned from <code>swift_common.create_module</code>. The modules (both Swift and C/Objective-C) emitted by the library that propagated this provider.    |
| <a id="SwiftInfo-transitive_modules"></a>transitive_modules |  <code>Depset</code> of values returned from <code>swift_common.create_module</code>. The transitive modules (both Swift and C/Objective-C) emitted by the library that propagated this provider and all of its dependencies.    |


<a id="#SwiftProtoInfo"></a>

## SwiftProtoInfo

<pre>
SwiftProtoInfo(<a href="#SwiftProtoInfo-module_mappings">module_mappings</a>, <a href="#SwiftProtoInfo-pbswift_files">pbswift_files</a>)
</pre>

Propagates Swift-specific information about a `proto_library`.

**FIELDS**


| Name  | Description |
| :------------- | :------------- |
| <a id="SwiftProtoInfo-module_mappings"></a>module_mappings |  <code>Sequence</code> of <code>struct</code>s. Each struct contains <code>module_name</code> and <code>proto_file_paths</code> fields that denote the transitive mappings from <code>.proto</code> files to Swift modules. This allows messages that reference messages in other libraries to import those modules in generated code.    |
| <a id="SwiftProtoInfo-pbswift_files"></a>pbswift_files |  <code>Depset</code> of <code>File</code>s. The transitive Swift source files (<code>.pb.swift</code>) generated from the <code>.proto</code> files.    |


<a id="#SwiftToolchainInfo"></a>

## SwiftToolchainInfo

<pre>
SwiftToolchainInfo(<a href="#SwiftToolchainInfo-action_configs">action_configs</a>, <a href="#SwiftToolchainInfo-cc_toolchain_info">cc_toolchain_info</a>, <a href="#SwiftToolchainInfo-clang_implicit_deps_providers">clang_implicit_deps_providers</a>,
                   <a href="#SwiftToolchainInfo-feature_allowlists">feature_allowlists</a>, <a href="#SwiftToolchainInfo-generated_header_module_implicit_deps_providers">generated_header_module_implicit_deps_providers</a>,
                   <a href="#SwiftToolchainInfo-implicit_deps_providers">implicit_deps_providers</a>, <a href="#SwiftToolchainInfo-linker_supports_filelist">linker_supports_filelist</a>, <a href="#SwiftToolchainInfo-package_configurations">package_configurations</a>,
                   <a href="#SwiftToolchainInfo-requested_features">requested_features</a>, <a href="#SwiftToolchainInfo-root_dir">root_dir</a>, <a href="#SwiftToolchainInfo-swift_worker">swift_worker</a>, <a href="#SwiftToolchainInfo-test_configuration">test_configuration</a>, <a href="#SwiftToolchainInfo-tool_configs">tool_configs</a>,
                   <a href="#SwiftToolchainInfo-unsupported_features">unsupported_features</a>)
</pre>


Propagates information about a Swift toolchain to compilation and linking rules
that use the toolchain.


**FIELDS**


| Name  | Description |
| :------------- | :------------- |
| <a id="SwiftToolchainInfo-action_configs"></a>action_configs |  This field is an internal implementation detail of the build rules.    |
| <a id="SwiftToolchainInfo-cc_toolchain_info"></a>cc_toolchain_info |  The <code>cc_common.CcToolchainInfo</code> provider from the Bazel C++ toolchain that this Swift toolchain depends on.    |
| <a id="SwiftToolchainInfo-clang_implicit_deps_providers"></a>clang_implicit_deps_providers |  A <code>struct</code> with the following fields, which represent providers from targets that should be added as implicit dependencies of any precompiled explicit C/Objective-C modules:<br><br>*   <code>cc_infos</code>: A list of <code>CcInfo</code> providers from targets specified as the     toolchain's implicit dependencies. *   <code>objc_infos</code>: A list of <code>apple_common.Objc</code> providers from targets specified     as the toolchain's implicit dependencies. *   <code>swift_infos</code>: A list of <code>SwiftInfo</code> providers from targets specified as the     toolchain's implicit dependencies.<br><br>For ease of use, this field is never <code>None</code>; it will always be a valid <code>struct</code> containing the fields described above, even if those lists are empty.    |
| <a id="SwiftToolchainInfo-feature_allowlists"></a>feature_allowlists |  A list of <code>SwiftFeatureAllowlistInfo</code> providers that allow or prohibit packages from requesting or disabling features.    |
| <a id="SwiftToolchainInfo-generated_header_module_implicit_deps_providers"></a>generated_header_module_implicit_deps_providers |  A <code>struct</code> with the following fields, which are providers from targets that should be treated as compile-time inputs to actions that precompile the explicit module for the generated Objective-C header of a Swift module:<br><br>*   <code>cc_infos</code>: A list of <code>CcInfo</code> providers from targets specified as the     toolchain's implicit dependencies. *   <code>objc_infos</code>: A list of <code>apple_common.Objc</code> providers from targets specified     as the toolchain's implicit dependencies. *   <code>swift_infos</code>: A list of <code>SwiftInfo</code> providers from targets specified as the     toolchain's implicit dependencies.<br><br>This is used to provide modular dependencies for the fixed inclusions (Darwin, Foundation) that are unconditionally emitted in those files.<br><br>For ease of use, this field is never <code>None</code>; it will always be a valid <code>struct</code> containing the fields described above, even if those lists are empty.    |
| <a id="SwiftToolchainInfo-implicit_deps_providers"></a>implicit_deps_providers |  A <code>struct</code> with the following fields, which represent providers from targets that should be added as implicit dependencies of any Swift compilation or linking target (but not to precompiled explicit C/Objective-C modules):<br><br>*   <code>cc_infos</code>: A list of <code>CcInfo</code> providers from targets specified as the     toolchain's implicit dependencies. *   <code>objc_infos</code>: A list of <code>apple_common.Objc</code> providers from targets specified     as the toolchain's implicit dependencies. *   <code>swift_infos</code>: A list of <code>SwiftInfo</code> providers from targets specified as the     toolchain's implicit dependencies.<br><br>For ease of use, this field is never <code>None</code>; it will always be a valid <code>struct</code> containing the fields described above, even if those lists are empty.    |
| <a id="SwiftToolchainInfo-linker_supports_filelist"></a>linker_supports_filelist |  <code>Boolean</code>. Indicates whether or not the toolchain's linker supports the input files passed to it via a file list.    |
| <a id="SwiftToolchainInfo-package_configurations"></a>package_configurations |  A list of <code>SwiftPackageConfigurationInfo</code> providers that specify additional compilation configuration options that are applied to targets on a per-package basis.    |
| <a id="SwiftToolchainInfo-requested_features"></a>requested_features |  <code>List</code> of <code>string</code>s. Features that should be implicitly enabled by default for targets built using this toolchain, unless overridden by the user by listing their negation in the <code>features</code> attribute of a target/package or in the <code>--features</code> command line flag.<br><br>These features determine various compilation and debugging behaviors of the Swift build rules, and they are also passed to the C++ APIs used when linking (so features defined in CROSSTOOL may be used here).    |
| <a id="SwiftToolchainInfo-root_dir"></a>root_dir |  <code>String</code>. The workspace-relative root directory of the toolchain.    |
| <a id="SwiftToolchainInfo-swift_worker"></a>swift_worker |  <code>File</code>. The executable representing the worker executable used to invoke the compiler and other Swift tools (for both incremental and non-incremental compiles).    |
| <a id="SwiftToolchainInfo-test_configuration"></a>test_configuration |  <code>Struct</code> containing two fields:<br><br>*   <code>env</code>: A <code>dict</code> of environment variables to be set when running tests     that were built with this toolchain.<br><br>*   <code>execution_requirements</code>: A <code>dict</code> of execution requirements for tests     that were built with this toolchain.<br><br>This is used, for example, with Xcode-based toolchains to ensure that the <code>xctest</code> helper and coverage tools are found in the correct developer directory when running tests.    |
| <a id="SwiftToolchainInfo-tool_configs"></a>tool_configs |  This field is an internal implementation detail of the build rules.    |
| <a id="SwiftToolchainInfo-unsupported_features"></a>unsupported_features |  <code>List</code> of <code>string</code>s. Features that should be implicitly disabled by default for targets built using this toolchain, unless overridden by the user by listing them in the <code>features</code> attribute of a target/package or in the <code>--features</code> command line flag.<br><br>These features determine various compilation and debugging behaviors of the Swift build rules, and they are also passed to the C++ APIs used when linking (so features defined in CROSSTOOL may be used here).    |


<a id="#SwiftUsageInfo"></a>

## SwiftUsageInfo

<pre>
SwiftUsageInfo(<a href="#SwiftUsageInfo-toolchain">toolchain</a>)
</pre>

A provider that indicates that Swift was used by a target or any target that it
depends on, and specifically which toolchain was used.


**FIELDS**


| Name  | Description |
| :------------- | :------------- |
| <a id="SwiftUsageInfo-toolchain"></a>toolchain |  The Swift toolchain that was used to build the targets propagating this provider.    |



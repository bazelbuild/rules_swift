<!-- Generated with Stardoc, Do Not Edit! -->

The providers described below are propagated and required by various Swift
build rules. Clients interested in writing custom rules that interface
with the rules in this package should use these providers to communicate
with the Swift build rules as needed.

On this page:

  * [SwiftGRPCInfo](#SwiftGRPCInfo)
  * [SwiftInfo](#SwiftInfo)
  * [SwiftToolchainInfo](#SwiftToolchainInfo)
  * [SwiftProtoInfo](#SwiftProtoInfo)
  * [SwiftUsageInfo](#SwiftUsageInfo)

<a id="SwiftGRPCInfo"></a>

## SwiftGRPCInfo

<pre>
SwiftGRPCInfo(<a href="#SwiftGRPCInfo-flavor">flavor</a>, <a href="#SwiftGRPCInfo-direct_pbgrpc_files">direct_pbgrpc_files</a>)
</pre>

Propagates Swift-specific information about a `swift_grpc_library`.

**FIELDS**


| Name  | Description |
| :------------- | :------------- |
| <a id="SwiftGRPCInfo-flavor"></a>flavor |  The flavor of GRPC that was generated. E.g. server, client, or client_stubs.    |
| <a id="SwiftGRPCInfo-direct_pbgrpc_files"></a>direct_pbgrpc_files |  `Depset` of `File`s. The Swift source files (`.grpc.swift`) generated from the `.proto` files in direct dependencies.    |


<a id="SwiftInfo"></a>

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
| <a id="SwiftInfo-direct_modules"></a>direct_modules |  `List` of values returned from `swift_common.create_module`. The modules (both Swift and C/Objective-C) emitted by the library that propagated this provider.    |
| <a id="SwiftInfo-transitive_modules"></a>transitive_modules |  `Depset` of values returned from `swift_common.create_module`. The transitive modules (both Swift and C/Objective-C) emitted by the library that propagated this provider and all of its dependencies.    |


<a id="SwiftProtoInfo"></a>

## SwiftProtoInfo

<pre>
SwiftProtoInfo(<a href="#SwiftProtoInfo-module_mappings">module_mappings</a>, <a href="#SwiftProtoInfo-pbswift_files">pbswift_files</a>, <a href="#SwiftProtoInfo-direct_pbswift_files">direct_pbswift_files</a>)
</pre>

Propagates Swift-specific information about a `proto_library`.

**FIELDS**


| Name  | Description |
| :------------- | :------------- |
| <a id="SwiftProtoInfo-module_mappings"></a>module_mappings |  `Sequence` of `struct`s. Each struct contains `module_name` and `proto_file_paths` fields that denote the transitive mappings from `.proto` files to Swift modules. This allows messages that reference messages in other libraries to import those modules in generated code.    |
| <a id="SwiftProtoInfo-pbswift_files"></a>pbswift_files |  `Depset` of `File`s. The transitive Swift source files (`.pb.swift`) generated from the `.proto` files.    |
| <a id="SwiftProtoInfo-direct_pbswift_files"></a>direct_pbswift_files |  `list` of `File`s. The Swift source files (`.pb.swift`) generated from the `.proto` files in direct dependencies.    |


<a id="SwiftToolchainInfo"></a>

## SwiftToolchainInfo

<pre>
SwiftToolchainInfo(<a href="#SwiftToolchainInfo-action_configs">action_configs</a>, <a href="#SwiftToolchainInfo-cc_toolchain_info">cc_toolchain_info</a>, <a href="#SwiftToolchainInfo-clang_implicit_deps_providers">clang_implicit_deps_providers</a>, <a href="#SwiftToolchainInfo-developer_dirs">developer_dirs</a>,
                   <a href="#SwiftToolchainInfo-entry_point_linkopts_provider">entry_point_linkopts_provider</a>, <a href="#SwiftToolchainInfo-feature_allowlists">feature_allowlists</a>,
                   <a href="#SwiftToolchainInfo-generated_header_module_implicit_deps_providers">generated_header_module_implicit_deps_providers</a>, <a href="#SwiftToolchainInfo-implicit_deps_providers">implicit_deps_providers</a>,
                   <a href="#SwiftToolchainInfo-package_configurations">package_configurations</a>, <a href="#SwiftToolchainInfo-requested_features">requested_features</a>, <a href="#SwiftToolchainInfo-root_dir">root_dir</a>, <a href="#SwiftToolchainInfo-swift_worker">swift_worker</a>,
                   <a href="#SwiftToolchainInfo-test_configuration">test_configuration</a>, <a href="#SwiftToolchainInfo-tool_configs">tool_configs</a>, <a href="#SwiftToolchainInfo-unsupported_features">unsupported_features</a>)
</pre>

Propagates information about a Swift toolchain to compilation and linking rules
that use the toolchain.

**FIELDS**


| Name  | Description |
| :------------- | :------------- |
| <a id="SwiftToolchainInfo-action_configs"></a>action_configs |  This field is an internal implementation detail of the build rules.    |
| <a id="SwiftToolchainInfo-cc_toolchain_info"></a>cc_toolchain_info |  The `cc_common.CcToolchainInfo` provider from the Bazel C++ toolchain that this Swift toolchain depends on.    |
| <a id="SwiftToolchainInfo-clang_implicit_deps_providers"></a>clang_implicit_deps_providers |  A `struct` with the following fields, which represent providers from targets that should be added as implicit dependencies of any precompiled explicit C/Objective-C modules:<br><br>*   `cc_infos`: A list of `CcInfo` providers from targets specified as the     toolchain's implicit dependencies. *   `objc_infos`: A list of `apple_common.Objc` providers from targets specified     as the toolchain's implicit dependencies. *   `swift_infos`: A list of `SwiftInfo` providers from targets specified as the     toolchain's implicit dependencies.<br><br>For ease of use, this field is never `None`; it will always be a valid `struct` containing the fields described above, even if those lists are empty.    |
| <a id="SwiftToolchainInfo-developer_dirs"></a>developer_dirs |  A list of `structs` containing the following fields:*   `developer_path_label`: A `string` representing the type of developer path. *   `path`: A `string` representing the path to the developer framework.    |
| <a id="SwiftToolchainInfo-entry_point_linkopts_provider"></a>entry_point_linkopts_provider |  A function that returns flags that should be passed to the linker to control the name of the entry point of a linked binary for rules that customize their entry point. This function must take the following keyword arguments: *   `entry_point_name`: The name of the entry point function, as was passed to     the Swift compiler using the `-entry-point-function-name` flag. It must return a `struct` with the following fields: *   `linkopts`: A list of strings that will be passed as additional linker flags     when linking a binary with a custom entry point.    |
| <a id="SwiftToolchainInfo-feature_allowlists"></a>feature_allowlists |  A list of `SwiftFeatureAllowlistInfo` providers that allow or prohibit packages from requesting or disabling features.    |
| <a id="SwiftToolchainInfo-generated_header_module_implicit_deps_providers"></a>generated_header_module_implicit_deps_providers |  A `struct` with the following fields, which are providers from targets that should be treated as compile-time inputs to actions that precompile the explicit module for the generated Objective-C header of a Swift module:<br><br>*   `cc_infos`: A list of `CcInfo` providers from targets specified as the     toolchain's implicit dependencies. *   `objc_infos`: A list of `apple_common.Objc` providers from targets specified     as the toolchain's implicit dependencies. *   `swift_infos`: A list of `SwiftInfo` providers from targets specified as the     toolchain's implicit dependencies.<br><br>This is used to provide modular dependencies for the fixed inclusions (Darwin, Foundation) that are unconditionally emitted in those files.<br><br>For ease of use, this field is never `None`; it will always be a valid `struct` containing the fields described above, even if those lists are empty.    |
| <a id="SwiftToolchainInfo-implicit_deps_providers"></a>implicit_deps_providers |  A `struct` with the following fields, which represent providers from targets that should be added as implicit dependencies of any Swift compilation or linking target (but not to precompiled explicit C/Objective-C modules):<br><br>*   `cc_infos`: A list of `CcInfo` providers from targets specified as the     toolchain's implicit dependencies. *   `objc_infos`: A list of `apple_common.Objc` providers from targets specified     as the toolchain's implicit dependencies. *   `swift_infos`: A list of `SwiftInfo` providers from targets specified as the     toolchain's implicit dependencies.<br><br>For ease of use, this field is never `None`; it will always be a valid `struct` containing the fields described above, even if those lists are empty.    |
| <a id="SwiftToolchainInfo-package_configurations"></a>package_configurations |  A list of `SwiftPackageConfigurationInfo` providers that specify additional compilation configuration options that are applied to targets on a per-package basis.    |
| <a id="SwiftToolchainInfo-requested_features"></a>requested_features |  `List` of `string`s. Features that should be implicitly enabled by default for targets built using this toolchain, unless overridden by the user by listing their negation in the `features` attribute of a target/package or in the `--features` command line flag.<br><br>These features determine various compilation and debugging behaviors of the Swift build rules, and they are also passed to the C++ APIs used when linking (so features defined in CROSSTOOL may be used here).    |
| <a id="SwiftToolchainInfo-root_dir"></a>root_dir |  `String`. The workspace-relative root directory of the toolchain.    |
| <a id="SwiftToolchainInfo-swift_worker"></a>swift_worker |  `File`. The executable representing the worker executable used to invoke the compiler and other Swift tools (for both incremental and non-incremental compiles).    |
| <a id="SwiftToolchainInfo-test_configuration"></a>test_configuration |  `Struct` containing two fields:<br><br>*   `env`: A `dict` of environment variables to be set when running tests     that were built with this toolchain.<br><br>*   `execution_requirements`: A `dict` of execution requirements for tests     that were built with this toolchain.<br><br>This is used, for example, with Xcode-based toolchains to ensure that the `xctest` helper and coverage tools are found in the correct developer directory when running tests.    |
| <a id="SwiftToolchainInfo-tool_configs"></a>tool_configs |  This field is an internal implementation detail of the build rules.    |
| <a id="SwiftToolchainInfo-unsupported_features"></a>unsupported_features |  `List` of `string`s. Features that should be implicitly disabled by default for targets built using this toolchain, unless overridden by the user by listing them in the `features` attribute of a target/package or in the `--features` command line flag.<br><br>These features determine various compilation and debugging behaviors of the Swift build rules, and they are also passed to the C++ APIs used when linking (so features defined in CROSSTOOL may be used here).    |


<a id="SwiftUsageInfo"></a>

## SwiftUsageInfo

<pre>
SwiftUsageInfo()
</pre>

A provider that indicates that Swift was used by a target or any target that it
depends on.

**FIELDS**




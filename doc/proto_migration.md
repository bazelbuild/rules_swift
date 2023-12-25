# Overview

This document aims to provide context to future contributors on why we decided to rewrite
the swift_proto_library and swift_grpc_library rules into the new_swift_proto_library rule,
as well as a guide for consumers of the deprecated rules to migrate to the new_swift_proto_library rule.

On this page:
  * [Why rewrite?](#why-rewrite)
  * [How to Migrate](#how-to-migrate)

## Why rewrite?

The new swift_proto_library rule was created to address several issues with the previous
swift_proto_library and swift_grpc_library rules which would be difficult if not impossible 
to fix while maintaining full backwards compatibility.

### 1. swift_protoc_gen_aspect

Firstly, the previous swift_proto_library rule used the aspect which traversed its direct 
proto_library dependencies and their transitive graph of proto_library dependencies,
and compiled all of these into swift modules. 

This meant that a single swift_proto_library target could generate and and compile swift source files
for *all* of the proto_library targets in potentially a very large dependency graph,
which could span across multiple repositories.

In practice, though, consumers typically preferred to have a 1:1 mapping of proto_library to swift_proto_library targets.
Additionally, this aspect meant that the module name and other compilation options could not be configured on a per-target basis,
since the aspect needed to be able to determine all of this information by just looking at the providers of the proto_library targets.

This lack of flexibility was extremely frustrating, especially for consumers who wanted to assign "Swift-like" module names
to the swift proto library modules. 

Using the deprecated_grpc example in this repository to demonstrate,
consumers had to import the generated service swift proto module with:

```
import examples_xplatform_deprecated_grpc_echo_server_services_swift
```

But with the new_swift_proto_library rule, 
they can assign an arbitrary module name to the target and import it with:

```
import ServiceServer
```

This removes the guesswork of trying to determine what the module name will be,
and it allow engineers to work with the new_swift_proto_library targets exactly the same
way they would if these were swift_library targets they had written by hand,
except the source files are generated for them.

### 2. Implicit, internal proto compiler and runtime dependencies.

The second main issue the new implementation is intended to address is the specific proto compiler,
proto compiler plugin, and compile time proto library dependencies the old rules required.

The old rules depended internally on the SwiftProtobuf and GRPC targets defined in the targets under
the third_party directory. This was problematic for consumers who wanted to use different versions
of protoc, the protoc plugins or compile time dependencies.

Specifically, this issue came to a head when implementing support for proto targets in
rules_swift_package_manager. There was a lengthy slack conversation here on the topic:
https://bazelbuild.slack.com/archives/CD3QY5C2X/p1692055426375909

The problem was that some Swift packages like Firebase have package dependencies on protobuf
libraries which contain the same code (though perhaps a different version) as the protobuf
targets defined in this repository which were dependencies of those rules.

This meant that consumers could *either* use the Swift package dependencies *or*
swift_proto_library / swift_grpc_library but not both or else they would encounter linker errors.

The new_swift_proto_library rule is completely configurable in terms of:
- the proto compiler target
- the proto compiler plugin target(s)
- the swift compile-time dependency target(s)
This is accomplished with a new swift_proto_compiler rule 
which is passed as an attribute to the new_swift_proto_library rule.

The swift_proto_compiler rule represents the combination of a protoc binary,
protoc plugin binary (e.g. the SwiftProtobuf or grpc-swift protoc plugin),
and the set of options passed to the protoc plugin.

We provide pre-configured swift_proto_compiler targets for:
- swift protos
- swift server grpc protos
- swift client grpc protos

And 3rd parties are welcome to create their own, configured based on their needs.
In the case of rules_swift_package_manager, this will enable the creation of a swift_proto_compiler target
configured to use the same dependencies as the other Swift packages.

Finally, this allows us to only have a single, new_swift_proto_library rule in lieu of the two
swift_proto_library and swift_grpc_library rules because the only real difference between them
is the plugin being passed to protoc and the options being passed to that plugin.

## How to Migrate

NOTE: If you leveraged the capability of the the deprecated swift_proto_library
to generate the protos for multiple proto_library targets from a single swift_proto_library target, 
you will need to create additional targets for a 1:1 mapping of proto_library targets to swift_proto_library targets.

## 1. swift_proto_library to new_swift_proto_library

Given two proto_library targets for foo.proto and bar.proto,
where bar.proto depends on foo.proto and the api.proto from the well known types.

```
proto_library(
    name = "foo_proto",
    srcs = ["foo.proto"],
)

proto_library(
    name = "bar_proto",
    srcs = ["bar.proto"],
    deps = [
        "@com_google_protobuf//:api_proto",
        ":foo_proto",
    ],
)
```

Which had the deprecated swift_proto_library targets:

```
swift_proto_library(
    name = "foo_swift_proto",
    deps = [":foo_proto"],
)

swift_proto_library(
    name = "bar_swift_proto",
    deps = [":bar_proto"],
)
```

These can be migrated to the following new_swift_proto_library targets:

```
new_swift_proto_library(
    name = "foo_swift_proto",
    protos = [":foo_proto"],
)

new_swift_proto_library(
    name = "bar_swift_proto",
    protos = [":bar_proto"],
    deps = [":foo_swift_proto"]
)
```

Note that you must declare deps between the new_swift_proto_library targets parallel to those between the proto_library targets,
and that the autogenerated Swift module names of the new targets are derived from the target labels of the swift_proto_library targets,
not the proto_library targets as before. 

If you wish, you may set the module_name attribute on the new_swift_proto_library targets as you would any other swift_library target.

## 2. swift_grpc_library to new_swift_proto_library

TODO

## F.A.Q.

As consumers raise questions during their migrations to the new_swift_proto_library rule,
we will add their answers here as a reference.
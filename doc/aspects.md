# Aspects

<!-- Generated file, do not edit directly. -->



The aspects described below are used within the build rule implementations.
Clients interested in writing custom rules that interface with the rules/provides
in this package might needs them to provide some of the same information.

On this page:

  * [swift_usage_aspect](#swift_usage_aspect)

<a name="swift_usage_aspect"></a>
## swift_usage_aspect

<pre style="white-space: normal">
swift_usage_aspect()
</pre>

Collects information about how Swift is used in a dependency tree.

When attached to an attribute, this aspect will propagate a `SwiftUsageInfo`
provider for any target found in that attribute that uses Swift, either directly
or deeper in its dependency tree. Conversely, if neither a target nor its
transitive dependencies use Swift, the `SwiftUsageInfo` provider will not be
propagated.

Specifically, the aspect propagates which toolchain was used to build those
dependencies. This information is typically always the same for any Swift
targets built in the same configuration, but this allows upstream targets that
may not be *strictly* Swift-related and thus don't want to depend directly on
the Swift toolchain (such as Apple universal binary linking rules) to avoid
doing so but still get access to information derived from the toolchain (like
which linker flags to pass to link to the runtime).

We use an aspect (as opposed to propagating this information through normal
providers returned by `swift_library`) because the information is needed if
Swift is used _anywhere_ in a dependency graph, even as dependencies of other
language rules that wouldn't know how to propagate the Swift-specific providers.


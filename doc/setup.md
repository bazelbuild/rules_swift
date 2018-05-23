# Workspace Setup


<a href="swift_rules_dependencies"></a>
## swift_rules_dependencies

<pre style="white-space: pre-wrap">
swift_rules_dependencies()
</pre>

Fetches repositories that are dependencies of the `rules_swift` workspace.

Users should call this macro in their `WORKSPACE` to ensure that all of the
dependencies of the Swift rules are downloaded and that they are isolated from
changes to those dependencies.


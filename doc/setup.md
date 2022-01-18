<!-- Generated with Stardoc, Do Not Edit! -->
# Workspace Setup
<a id="#swift_rules_dependencies"></a>

## swift_rules_dependencies

<pre>
swift_rules_dependencies()
</pre>

Fetches repositories that are dependencies of `rules_swift`.

Users should call this macro in their `WORKSPACE` to ensure that all of the
dependencies of the Swift rules are downloaded and that they are isolated
from changes to those dependencies.




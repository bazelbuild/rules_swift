# Debugging Remotely Built Swift

This is a guide to using remotely built Swift modules in local debug builds.

By default `lldb` depends on debugging options embedded in `.swiftmodule` files. These options include paths that are only valid on the build host. For local builds, this all just works, but for remote builds, it doesn't.

The solution is two parts:

1. Pass `-no-serialize-debugging-options` globally, to prevent embedded
   paths and output reproducible `swiftmodule` files
2. Setup a `lldbinit` that restores any of the options that were
   intended to be set in the `swiftmodule` files

An lldb bug has been filed here: https://bugs.swift.org/browse/SR-11485

### Disable Debugging Options Globally

To globally disable debugging options, use the `swift.cacheable_swiftmodules` feature in rules_swift. For example, your `.bazelrc` could look like this:

```
build --features=swift.cacheable_swiftmodules
```

What this does is ensure all modules are built explicitly with `-no-serialize-debugging-options`. It has to be explicit because `swiftc` enables `-serialize-debugging-options` by default in some cases.

### LLDB Settings

Additional settings may be required, depending on your build setup. For example, an Xcode Run Script may look like:

```
echo "settings set target.sdk-path $SDKROOT"
echo "settings set target.swift-framework-search-paths $TEST_FRAMEWORK_SEARCH_PATHS $FRAMEWORK_SEARCH_PATHS"
```

Other settings you can try customizing are:

* `target.clang-module-search-paths`
* `target.debug-file-search-paths`
* `target.sdk-path`
* `target.swift-extra-clang-flags`
* `target.swift-framework-search-paths`
* `target.swift-module-search-paths`
* `target.use-all-compiler-flags`
* `symbols.clang-modules-cache-path`

These settings would be written to some project specific lldbinit file which you can include directly in Xcode's scheme.

NOTE: `$TEST_FRAMEWORK_SEARCH_PATHS` is required in order to debug code
that imports XCTest. If you do not include these directories you may end
up with errors when attempting to po such as:

```
(lldb) po self
error: expression failed to parse:
error: Couldn't realize type of self.
```

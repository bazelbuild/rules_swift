# Explicit modules

This document covers how to use explicit modules in Swift with bazel.
See [background](#background) for more details on why you might want
this.

# Usage

To opt in to explicit modules add this in your `.bazelrc`:

```
build --features=swift.emit_c_module --host_features=swift.emit_c_module
build --features=swift.use_c_modules --host_features=swift.use_c_modules
```

If possible you should also enable this feature (currently this might
negatively impact the IDE experience, more testing is needed):

```
build --features=swift.use_explicit_swift_module_map --host_features=swift.use_explicit_swift_module_map
```

## Debugging

In order to debug your application built with explicit modules in `lldb`
you do need to correctly set the source map so that it can discover the
correct Xcode path (this is done automatically if you're debugging with
[`rules_xcodeproj`](https://github.com/MobileNativeFoundation/rules_xcodeproj)):

```
settings set target.source-map /PLACEHOLDER_DEVELOPER_DIR /Applications/Xcode-26.4.0-RC1.app/Contents/Developer
```

This must have the actual user-local path to Xcode, even if that differs
from where it was built. It is still up to you to make sure the versions
are compatible.

NOTE: Until Swift 6.3 / Xcode 26.4, with Swift macros absolute paths
would still be embedded in the swiftmodule files. This means debugging
in `lldb` with explicit modules would not work with cached swiftmodules
and is therefore disabled.

## Using explicit dependencies

By default we implicitly add all possible precompiled modules to the
dependencies of every `swift_*` target. This allows the easiest
onboarding to explicit modules, but also means you're doing more work
than you need to for your build. This extra work is especially
noticeable for clean builds, since we're building more PCMs than needed,
and for remote execution where you will upload / download more PCMs than
you need.

If you would like to manage these dependencies yourself, add this to
your `.bazelrc`:

```
build --features=-swift.add_default_precompiled_modules --host_features=-swift.add_default_precompiled_modules
```

Then add this to your `MODULE.bazel`:

```bzl
system_sdk = use_extension("@rules_swift//swift:extensions.bzl", "system_sdk")
use_repo(system_sdk, "system_sdk")
```

Now you are responsible for manually adding system dependencies to your
targets' `deps`, for example:

```bzl
swift_binary(
    name = "foo",
    srcs = ["main.swift"],
    deps = ["@system_sdk//:SwiftUI"],
)
```

```bzl
objc_library(
    name = "lib",
    srcs = ["lib.m"],
    hdrs = ["lib.h"],
    aspect_hints = [":lib_hint"],
    deps = ["@system_sdk//:Foundation"],
)
```

## Configuring what SDKs are available

By default only the macOS and iOS SDKs are added to the `@system_sdk`
repository, which saves time generating the underlying `BUILD` file. If
you build for more Apple platforms, configure them in your
`MODULE.bazel`:

```bzl
system_sdk = use_extension("@rules_swift//swift:extensions.bzl", "system_sdk")
system_sdk.configure_sdks(names = [
    "MacOSX",
    "iPhoneOS",
    "iPhoneSimulator",
    "WatchOS",
    "WatchSimulator",
])
use_repo(system_sdk, "system_sdk")
```

Alternatively you can include all SDKs with:

```bzl
system_sdk = use_extension("@rules_swift//swift:extensions.bzl", "system_sdk")
system_sdk.configure_sdks(include_all = True)
use_repo(system_sdk, "system_sdk")
```

## Ignoring broken SDK modules

If you're using the implicitly added deps, `rules_swift` builds every
module it finds. In this case if the SDK has any modules that are
broken, you need to disable discovering  them. To do this add something
like this to your `MODULE.bazel`:

```bzl
system_sdk.configure_sdks(
    exclude_modules = {
        "WatchOS": [
            "BrowserEngineKit",
        ],
        "WatchSimulator": [
            "BrowserEngineKit",
            "CoreAudio_Private",
        ],
        "iPhoneSimulator": [
            "CoreAudio_Private",
        ],
    },
)
```

To do this when vendoring your SDK, pass `--exclude-module
WatchOS:BrowserEngineKit` etc to the scan script.

## Providing a precomputed BUILD file

By default the `@system_sdk` module extension scans all local Xcode
versions and provides the SDK for whichever is chosen with
`--xcode_version`. If you have a configuration where you do not want
this local scanning to happen, you can provide the computed `BUILD` file
yourself:

```bzl
system_sdk = use_extension("//swift:extensions.bzl", "system_sdk")
system_sdk.configure_xcode(
    build_file = "//path/to/vendored.BUILD",
    version = "26.4.0.17E192",
)
use_repo(system_sdk, "system_sdk")
```

This is useful if you trigger remote macOS builds from Linux hosts. It
is up to you to generate the file with whatever SDKs you need.

This file can be generated with this helper:

```sh
bazel run -- \
 @rules_swift//tools/explicit_modules:scan \
 --output \
 vendored.BUILD \
 --developer-dir \
 /Applications/Xcode-26.4.0-RC1.app/Contents/Developer \
 MacOSX iPhoneOS iPhoneSimulator
```

NOTE: The format of this `BUILD` file isn't considered stable, so if you
choose to vendor it yourself you should regenerate it whenever you
update `rules_swift`.

## Handling `-application-extension`

Currently only 1 variant of PCMs are produced. These PCMs do not pass
`-application-extension` and therefore are not produced with that
enabled. This can cause build failures for `swift_library` targets that
pass this manually that look like this:

```
<unknown>:0: error: Objective-C App Extension was disabled in PCH file but is currently enabled
<unknown>:0: error: module file bazel-out/...swift.pcm cannot be loaded due to a configuration mismatch with the current compilation
```

To work around this you can change your `copts` to this:

```bzl
copts = [
    "-application-extension",
    "-Xcc",
    "-fno-application-extension",
],
```

This _should_ be harmless because Swift still validates application
extension usage when type checking.

## Handling frameworks with missing dependencies

When using explicit modules, precompiled frameworks are evaluated at a
different time than they are with implicit modules. Specifically the
`modulemap` or `swiftinterface` files are compiled in the context of
their own target, instead of in the context of the importing target.

This means any dependencies the precompiled framework has, likely on
other precompiled frameworks, have to be correctly defined in the
`BUILD` file.

Currently Swift Package Manager doesn't support dependencies on
`binaryTarget`s, which means if you're using
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager),
you have to manually add the dependencies through your `MODULE.bazel`
file. The build failures do not always indicate exactly what
dependencies are missing, but the end result will look something like
this:

```bzl
swift_deps.configure_package(
    name = "swiftpkg_facebook_ios_sdk",
    target_deps = {
        "FBAEMKit": [":FBSDKCoreKit_Basics"],
        "FBSDKCoreKit": [
            ":FBAEMKit",
            ":FBSDKCoreKit_Basics",
        ],
        "FBSDKGamingServicesKit": [
            ":FBSDKCoreKit",
            ":FBSDKCoreKit_Basics",
            ":FBSDKShareKit",
        ],
        "FBSDKLoginKit": [
            ":FBSDKCoreKit",
            ":FBSDKCoreKit_Basics",
        ],
        "FBSDKShareKit": [
            ":FBSDKCoreKit",
            ":FBSDKCoreKit_Basics",
        ],
    },
)
```

# Background

## Implicit modules

Previously when you had a trivial Swift file that imported a non-Swift
system framework, such as `Foundation` (for now):

```swift
import Foundation

let str: NSString = "Hello, World!"
print(str)
```

The Swift compiler would implicitly create an underlying precompiled
module (`.pcm` file) for `Foundation` in order for Swift to interact
with non-Swift APIs. Practically speaking implicit modules have a few
issues:

- These PCM files are non-hermetic, so it is possible you can get into
  bad states where the implicit modules are somehow not cache
  invalidated, leading to surprising build failures. This primarily
  happens with Xcode and not bazel, but is still possible and very hard
  to debug.
- The modules were not shared with remote execution / remote caching or
  between parallel bazel compile sandboxes. This means we end up doing
  tons of duplicate work building the identical PCMs for different
  compile actions.
- The same PCMs you need for compilation are also needed by `lldb`, but
  they might have be shared, which means `lldb` could also end up
  compiling the PCMs, leading to more duplicate work.

## Explicit modules

Explicit modules moves the concern of how PCMs are produced, and which
PCMs are used to the build system. In bazel's case this means that we
define a target for creating every possible system framework's PCM file,
and we propagate those downstream to the `swift_library` targets. Then
we pass some various compiler flags to make sure that the Swift compiler
uses our precompiled modules instead of trying to create the implicit
ones it previously would have.

This allows us to share PCMs across machines, and with compilation and
`lldb`.

## Differences from Xcode

Unlike bazel, Xcode doesn't require you strictly define your
dependencies. For explicit modules support, Xcode scans all the source
files being built, and builds only the necessary PCMs "just in time."
Bazel doesn't support this type of dynamic dependencies, so all system
modules have to be understood ahead of time, which is why we generate
the `@system_sdk` repository, and require you add them to your `deps`
(or implicitly do that for you).

Xcode also doesn't attempt to produce portable PCMs, which we do in
bazel.

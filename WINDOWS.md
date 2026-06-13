# Building Swift on Windows with rules_swift

This document is a working note on the state of **native Windows** support in
rules_swift and what it takes to build Swift code on a Windows host.

## TL;DR

Building Swift **on Windows, for Windows** is the same model as building for
Apple platforms on macOS: you do it **natively on the host**, using a Swift
toolchain that is *installed on the machine* (not downloaded by Bazel), and
Bazel achieves reproducibility by tracking/hashing the installed binaries it
invokes — exactly how `apple_support` treats Xcode.

This is **orthogonal to the cross-compilation work in this PR.** The
`swift.wasm_sdk` / `swift.android_sdk` Swift-SDK mechanism is a *convenience* for
the targets that can be cross-compiled from any host (WebAssembly, Android,
static Linux). Apple and Windows are each built on their own platform, so they
use a **host toolchain**, not a downloaded destination-SDK. There is no official
Windows "Swift SDK" artifact bundle, and that's expected — Windows is a host
target, not a cross destination.

## What already exists upstream

rules_swift already has a Windows host toolchain path; it is **not** something
this PR needs to add:

- **Autoconfiguration** — `swift/internal/swift_autoconfiguration.bzl`
  (`_create_windows_toolchain`) discovers a locally-installed Swift toolchain
  when `swiftc.exe` is on `PATH`. It derives the toolchain `root` from
  `swiftc.exe`'s location, reads `SDKROOT` / `Path` / `ProgramData` from the
  environment, and reads `XCTEST_VERSION` from the installed SDK's `Info.plist`.
  On a non-Windows host (no `swiftc.exe` on `PATH`) it emits a no-op comment, so
  it is safe cross-platform.
- **A Windows `swift_toolchain`** is generated with `os = "windows"`,
  `arch = "x86_64"`, `tool_executable_suffix = ".exe"`, and the discovered
  `root` / `sdkroot` / `env`.
- **Windows link flags** — `swift/toolchains/swift_toolchain.bzl`
  (`_swift_windows_linkopts_cc_info`) supplies the MSVC-style linker flags:
  - `-LIBPATH:<sdkroot>/usr/lib/swift/windows/<arch>`
  - `-LIBPATH:<...>/Library/XCTest-<version>/usr/lib/swift/windows/<arch>`
  - the runtime start object `<sdkroot>/usr/lib/swift/windows/<arch>/swiftrt.obj`
- **A registered toolchain** — `swift/toolchains/BUILD` registers
  `windows-swift-toolchain-x86_64` (`exec`/`target` = `@platforms//os:windows` +
  `@platforms//cpu:x86_64`) pointing at `@rules_swift_local_config//:windows-toolchain`.

The C/C++ side is handled by Bazel's built-in **MSVC C++ toolchain**, which
discovers Visual Studio via `vswhere` / `BAZEL_VC`. rules_swift's Windows
`swift_toolchain` composes with that cc toolchain for linking.

So the expectation on a properly-provisioned Windows box is that a plain
`swift_library` / `swift_binary` builds with no extra configuration.

## Prerequisites on the Windows machine

1. **Visual Studio 2022+ (Build Tools is enough)** — provides MSVC and the
   Windows SDK (the C runtime, Win32 headers/libs, `link.exe`). This is what
   Bazel's MSVC cc toolchain and the Swift linker consume.
2. **Swift for Windows** (the swift.org installer) — installs `swiftc.exe` and
   the Swift Windows runtime/SDK, and sets `SDKROOT` (and the module maps for
   `ucrt` / `winsdk` / `visualc`). Use the release that matches anything you
   pin elsewhere.
3. **Run Bazel from an environment that has both** — i.e. a "x64 Native Tools
   Command Prompt for VS" (or a shell that has sourced `vcvars64.bat`) **with the
   Swift installer's environment** also present, so `swiftc.exe` is on `PATH` and
   `SDKROOT` / `Path` / `ProgramData` are set when the repository rule runs.
4. **Python 3** on `PATH` — the autoconfiguration shells out to it to read the
   XCTest version from the SDK `Info.plist`.

## How to build / verify

From the rules_swift checkout, in a provisioned VS+Swift shell:

```bat
bazel build //examples/...
bazel test  //test/...
```

A minimal smoke target is the embedded/simple `swift_binary` examples. If the
host toolchain resolves, `bazel cquery 'config(//examples/...)'` and the build
should select `windows-swift-toolchain-x86_64`.

## Known gaps / things to verify (the actual PC work)

The Windows scaffolding exists but is **not currently exercised in CI** — the
`windows_last_green` task in `.bazelci/presubmit.yml` is commented out, and the
`windows_common` config only builds `//tools/...`. So treat this as "verify and
fix bit-rot," not "implement from scratch." Concrete things to check:

1. **Does autoconfiguration resolve cleanly** with a current Swift-for-Windows
   layout? The `Info.plist` path math
   (`SDKROOT/../../../Info.plist`) and the `usr/lib/swift/windows/<arch>` layout
   may have shifted across Swift releases.
2. **End-to-end link** of a `swift_binary` (does `swiftrt.obj` + the `-LIBPATH:`
   flags + the MSVC cc toolchain produce a runnable `.exe`?).
3. **`linkshared` → `.dll`.** Confirm `swift_binary(linkshared = True)` produces
   a proper Windows DLL (with an import lib) — the same attribute used for the
   Android `.so` / wasm reactor in this PR. This is the path a SwiftUI-on-Windows
   renderer would consume (see the consumer-side counterpart doc).
4. **arm64 Windows.** Only `x86_64` is registered; `aarch64` Windows would be an
   additive toolchain entry.
5. **XCTest** discovery/version on Windows (the `XCTest-<version>` LIBPATH).
6. **Re-enable a Windows CI task** once the above passes, even if scoped to a
   small example, so it doesn't regress again.

## Hermeticity

This follows the Xcode model: the toolchain is discovered from the environment
and referenced by absolute `root` / `sdkroot` paths. To make the *build outputs*
reproducible despite the external install, Bazel can digest the referenced
toolchain/SDK files (the binaries and libraries actually invoked), the same way
`apple_support` tracks Xcode. Tightening input tracking is a follow-up
refinement, not a blocker to building.

## Relationship to this PR

Nothing here depends on the Swift-SDK cross-compilation changes, and vice
versa. This note lives on the branch only to capture the current Windows-host
state and the verification checklist for picking the work up on an actual
Windows machine.

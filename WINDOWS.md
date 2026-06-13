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
   XCTest version from the SDK `Info.plist`. A real interpreter is required; the
   Microsoft Store `python3.exe` execution-alias stub is detected and skipped.
5. **`bash` on `PATH` and `BAZEL_SH` set** (e.g. Git for Windows' `bash.exe`) —
   needed only for `bazel test`, whose generic test wrapper is a shell script.

## How to build / verify

From the rules_swift checkout, in a provisioned VS+Swift shell:

```bat
set BAZEL_SH=C:\Program Files\Git\bin\bash.exe
bazel build //examples/xplatform/hello_world //examples/xplatform/shared_library
bazel test  //examples/xplatform/xctest
```

`hello_world` is the minimal `swift_binary` smoke target, `shared_library`
exercises the `linkshared` → `.dll` path, and `xctest` exercises `swift_test`
(XCTest discovery, the runner, and execution). If the host toolchain resolves,
the build selects `windows-swift-toolchain-x86_64`.

## Status (verified on a native Windows host)

The checklist below was worked through end-to-end on a real Windows 11 host
(Swift 6.3.2 for Windows + Visual Studio 2022 Build Tools / MSVC 14.44, Bazel
9.1.1). Verifying it surfaced several pieces of bit-rot and a handful of
genuinely missing Windows code paths; all are fixed on this branch.

1. **Autoconfiguration resolves cleanly.** ✅ The `Info.plist` path math and the
   `usr/lib/swift/windows/<arch>` layout still match a current Swift release.
   Two latent bugs were fixed, both of which had left `xctest_version` empty:
   - `_get_python_bin` returned the Microsoft Store `python3.exe` *execution
     alias* (a stub that exits nonzero) instead of a real interpreter. It now
     probes candidates and skips non-working ones.
   - `SDKROOT` from the environment ends in a backslash, which was interpolated
     into a Python raw-string literal (`r'...\'`) — a syntax error. The SDK root
     is now normalized (forward slashes, no trailing separator) before use.
2. **End-to-end `swift_binary` link.** ✅ `//examples/xplatform/hello_world`
   builds to a runnable `.exe` and prints "Hello, world!". Two fixes were
   required: the toolchain rejected the MSVC cc toolchain (`msvc-cl`) because of
   a hard `clang`-only check (now skipped on Windows), and the entry-point alias
   used GNU `ld`'s `--defsym`, which MSVC `link.exe` rejects (now
   `/ALTERNATENAME` on Windows).
3. **`linkshared` → `.dll`.** ✅ `swift_binary(linkshared = True)` produces a
   Windows `.dll` plus an import `.lib`; see the new
   `//examples/xplatform/shared_library` example.
4. **arm64 Windows.** ⚠️ Implemented but **unverified** (no arm64 host was
   available). Autoconfiguration now detects the host CPU instead of hardcoding
   `x86_64`, the toolchain understands the `aarch64` library/`bin64a` layout,
   and a `windows-swift-toolchain-aarch64` toolchain is registered.
5. **XCTest.** ✅ The `XCTest-<version>` `LIBPATH`/`-I` paths resolve.
   `swift_test` runs end-to-end (`//examples/xplatform/xctest` passes). Getting
   there required: adding the XCTest include paths to the symbol-graph-extract
   action (test discovery), emitting the `-msvc` target-triple environment (the
   symbol-graph tool matches the module triple exactly), porting the
   `//tools/test_observer` runner to Windows (`SRWLOCK`, `GetProcAddress`, a
   swift-corelibs XCTest runner shared with Linux), running the discovery tool
   with the Swift runtime on `PATH`, sanitizing spaces out of object paths
   (`lib.exe`/`link.exe` response-file parsing), making the persistent worker
   long-path (`\\?\`) aware, and suppressing the benign `LNK4217` that static
   linking of `dllimport` symbols produces.
6. **Windows CI.** ⚠️ Re-enabled in `.bazelci/presubmit.yml` (a `windows` task
   that builds the Swift examples and runs the `xctest` test). The Swift-install
   prologue and BazelCI Windows image provisioning are the one piece **not**
   validated here, since that requires the CI infrastructure rather than a local
   host; it may need adjustment when first run.

A general (not Windows-only) requirement also surfaced: `bazel test` on Windows
needs a `bash` for the test wrapper, so `BAZEL_SH` must point at a `bash.exe`
(e.g. Git for Windows). `worker` sandboxing is disabled on Windows in `.bazelrc`
(`build:windows --noworker_sandboxing`) because a running executable cannot be
deleted to clean the sandbox.

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

# Standalone Swift toolchain

`rules_swift` ships a Bzlmod module extension that downloads a standalone
Swift toolchain from [swift.org](https://swift.org/download) and registers
it with Bazel. This gives you a hermetic Swift toolchain that does not rely
on the host's pre-installed compiler (or Xcode), which is useful for
reproducible builds, CI, and cross-platform builds.

The extension supports both macOS (`.pkg`) and Linux (`.tar.gz`) toolchain
archives.

## Quick start

In your `MODULE.bazel`:

```bzl
swift = use_extension(
    "@rules_swift//swift:extensions.bzl",
    "swift",
)

swift.toolchain(
    name = "swift_toolchain",
    swift_version = "6.2.4",
)

use_repo(
    swift,
    "swift_toolchain",
    # Add one entry per platform you intend to build on. The repo names are
    # of the form `<name>_<platform>`.
    "swift_toolchain_xcode",
    "swift_toolchain_ubuntu22.04",
    "swift_toolchain_ubuntu22.04-aarch64",
)

register_toolchains(
    "@swift_toolchain//:cc_toolchain_embedded_xcode",
    "@swift_toolchain//:swift_toolchain_embedded_xcode",
    "@swift_toolchain//:cc_toolchain_embedded_ubuntu22.04",
    "@swift_toolchain//:swift_toolchain_embedded_ubuntu22.04",
    "@swift_toolchain//:cc_toolchain_embedded_ubuntu22.04-aarch64",
    "@swift_toolchain//:swift_toolchain_embedded_ubuntu22.04-aarch64",
)
```

You only need to `use_repo` and `register_toolchains` for the platforms you
actually build on. Each platform repo name is `<toolchain_name>_<platform>`.

## The `swift.toolchain` tag

| Attribute | Type | Description |
|---|---|---|
| `name` | string, required | Repository name of the generated parent toolchain repo. Per-platform repos are named `<name>_<platform>`. |
| `swift_version` | string | The Swift release version (e.g. `6.2.4`) or a snapshot identifier (see [Snapshots](#snapshot-toolchains)). Mutually exclusive with `swift_version_file`. |
| `swift_version_file` | label | A label pointing at a file containing the version string (typically a `.swift-version` file checked into the repo). Mutually exclusive with `swift_version`. |
| `platform_sha256` | string_dict | Optional map of platform → SHA-256. Required for snapshots and any version not present in the bundled `SWIFT_RELEASES` table. When set, it overrides the bundled checksums. |

### Supported platforms

The platform keys come from the swift.org download URLs and currently include:

* `xcode` (macOS, both Apple silicon and Intel)
* `ubuntu22.04`, `ubuntu22.04-aarch64`
* `ubuntu24.04`, `ubuntu24.04-aarch64`
* `debian12`, `debian12-aarch64`
* `fedora39`, `fedora39-aarch64`
* `amazonlinux2`, `amazonlinux2-aarch64`
* `ubi9`, `ubi9-aarch64`

Bazel does not currently have constraints to auto-select between Linux
distributions, so you must explicitly `register_toolchains` for the
distribution(s) your CI and developers run on.

The macOS (`xcode`) archive is a `.pkg` and can only be extracted on a
macOS host — pulling it on Linux will fail at fetch time.

### Generated targets

For each platform, the parent repo (`@<name>`) exposes:

* `cc_toolchain_embedded_<platform>` — C/C++ toolchain used for the embedded
  Swift target platform.
* `swift_toolchain_embedded_<platform>` — Swift toolchain for the embedded
  target.
* `swift_toolchain_exec_<platform>` — Swift toolchain for use as an exec
  toolchain (i.e. compiling tools that run on the build host).

The per-platform repo (`@<name>_<platform>`) holds the extracted Swift
toolchain itself and is what the toolchain targets above point at.

### Pinning the version with a file

If you already track the toolchain version in a `.swift-version` file (the
same convention used by `swiftly`), point the extension at it directly:

```bzl
swift.toolchain(
    name = "swift_toolchain",
    swift_version_file = "//:.swift-version",
)
```

## Adding versions not bundled with `rules_swift`

`rules_swift` bundles SHA-256 checksums for a curated list of releases (see
`swift/internal/extensions/swift_releases.bzl`). To use a release that
isn't bundled, supply your own `platform_sha256` map:

```bzl
swift.toolchain(
    name = "swift_toolchain",
    swift_version = "6.3",
    platform_sha256 = {
        "xcode": "…",
        "ubuntu22.04": "…",
        "ubuntu22.04-aarch64": "…",
    },
)
```

Generate the dictionary with the bundled `swift-releases` helper:

```sh
bazel run @rules_swift//tools/swift-releases -- list 6.3
```

This downloads each release archive and prints a ready-to-paste mapping
from platform to SHA-256.

## Snapshot toolchains

You can install development snapshots by passing the snapshot identifier
as the version. Two forms are accepted, mirroring `swiftly`:

* `main-snapshot-YYYY-MM-DD` → `main` development snapshots.
* `<branch>-snapshot-YYYY-MM-DD` → branch snapshots, e.g.
  `6.0-snapshot-2024-08-01`.

Snapshots are not in the bundled checksum table, so you must provide
`platform_sha256`. The `swift-releases` tool requires `--platform` for
snapshots (it can't enumerate platforms automatically):

```sh
bazel run @rules_swift//tools/swift-releases -- list \
    main-snapshot-2024-08-01 --platform xcode --platform ubuntu22.04
```

## Cross-compiling with Swift SDKs (WebAssembly and Android)

swift.org publishes "Swift SDK" artifact bundles (the bundles consumed by
`swift sdk install`) that let the host compiler cross-compile for platforms
it cannot target by itself. The `swift` extension can download these and
define matching Swift and C/C++ toolchains, so that plain `swift_library`
and `swift_binary` targets build for those platforms under `--platforms`.

Add the `wasm_sdk` and/or `android_sdk` tags, referencing the `toolchain`
tag by name (the Swift module format is not stable across compiler
versions, so the SDK is always downloaded for exactly the toolchain's
version):

```bzl
swift.toolchain(
    name = "swift_toolchain",
    swift_version = "6.3.2",
)

swift.wasm_sdk(
    toolchain_name = "swift_toolchain",
)

swift.android_sdk(
    toolchain_name = "swift_toolchain",
    # api_level = 28,  # the default
)

register_toolchains(
    # WebAssembly (wasm32-unknown-wasip1), per host platform you build on.
    "@swift_toolchain//:swift_toolchain_wasm32_xcode",
    "@swift_toolchain//:cc_toolchain_wasm32_xcode",
    # Android, per architecture and host platform.
    "@swift_toolchain//:swift_toolchain_android_aarch64_xcode",
    "@swift_toolchain//:cc_toolchain_android_aarch64_xcode",
    "@swift_toolchain//:swift_toolchain_android_x86_64_xcode",
    "@swift_toolchain//:cc_toolchain_android_x86_64_xcode",
)
```

Then build with a platform carrying the matching constraints, for example:

```bzl
platform(
    name = "wasm32-wasip1",
    constraint_values = [
        "@platforms//cpu:wasm32",
        "@platforms//os:wasi",
    ],
)

platform(
    name = "android-aarch64",
    constraint_values = [
        "@platforms//cpu:aarch64",
        "@platforms//os:android",
    ],
)
```

```sh
bazel build //my:binary --platforms=//:wasm32-wasip1
```

See `examples/cross_compilation` for a complete example, including building
through a platform transition.

Details worth knowing:

* The Swift standard library is linked statically from the SDK, matching
  the behavior of `swiftc` with these SDKs. WebAssembly binaries are
  self-contained `wasm32-wasip1` modules (runnable with `wasmtime` et al.).
* Android binaries link against the NDK's `libc++_shared.so`, which must be
  packaged with the application; the NDK repository exposes it as
  `@<toolchain_name>_android_ndk_<host_os>//:libcxx_shared_<arch>`.
* The `android_sdk` tag downloads the Android NDK (for its sysroot and
  clang) in addition to the Swift SDK. The NDK is only fetched when an
  Android target is actually built; WebAssembly-only builds do not download
  it. The NDK version and checksums can be overridden with the
  `ndk_version` and `ndk_sha256s` attributes.
* As with toolchains, checksums for the SDK bundles are bundled for a
  curated list of releases (see
  `swift/internal/extensions/swift_sdk_releases.bzl`); for other releases,
  pass `sha256` explicitly.

## Using the extension from a non-root module

The extension is intended for the root module — it fails if a non-root
module tries to declare toolchains. If you depend on `rules_swift` from a
library module and want the toolchain only when developing that module
locally, declare it as a dev dependency:

```bzl
swift = use_extension(
    "@rules_swift//swift:extensions.bzl",
    "swift",
    dev_dependency = True,
)
```

## Building with the standalone toolchain

Once registered, normal `swift_binary`, `swift_library`, and `swift_test`
targets pick up the toolchain through Bazel's standard toolchain
resolution — no per-target configuration is needed.

This is independent of the macOS `--action_env=TOOLCHAINS=…` mechanism
described in the top-level README, which selects between Xcode-managed
toolchains rather than between hermetic Bazel-managed ones.

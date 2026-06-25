# Cross-compilation example (Android)

Builds plain `swift_library` / `swift_binary` targets for Android using the
Swift SDK toolchain registered by this repository's `MODULE.bazel` (via the
`swift` extension's `android_sdk` tag). See `doc/standalone_toolchain.md` for the
toolchain setup.

All targets are tagged `manual` because they download the Swift SDK bundle and
require the Android cc toolchain to be registered.

### The Android C/C++ toolchain

rules_swift provides only the Swift Android toolchain; C/C++ compilation and
linking (and the NDK sysroot the Swift compiler reads) come from a separately
registered Android cc toolchain. This example uses `@androidndk//:all` from
keith's
[`hermetic_android_toolchains`](https://github.com/keith/hermetic_android_toolchains),
wired in this repository's `MODULE.bazel`:

```starlark
android = use_extension("@hermetic_android_toolchains//:extensions.bzl", "android")
android.sdk(version = "35", build_tools_version = "35.0.0")
android.ndk(version = "r27c", api_level = 28)
use_repo(android, "androidndk")
register_toolchains("@androidndk//:all")
```

Any rules_android_ndk-based Android cc toolchain works the same way. To package
the NDK's `libc++_shared.so` into an APK, use the `select_android_runtime_lib`
rule from `@rules_swift//swift/toolchains:android_runtime_lib.bzl` (it reads the
resolved cc toolchain); see `android_app/README.md`.

## Targets

| Target | Output | Demonstrates |
|---|---|---|
| `:Greeter` | `.swiftmodule` + `.a` | A normal `swift_library` reused across targets |
| `:libSwiftJNI.so` | `libSwiftJNI.so` | An Android **JNI shared library** (`swift_binary(linkshared)`) that calls `:Greeter` |

```sh
# Android JNI shared library:
bazel build //examples/cross_compilation:libSwiftJNI.so
```

`:libSwiftJNI.so` builds `:SwiftJNI` under the `:android-aarch64` platform; you
can equivalently pass `--platforms=//examples/cross_compilation:android-aarch64`
on the command line.

## Android app

`android_app/` is a complete, runnable APK that loads `libSwiftJNI.so`, calls
into it, and shows the Swift greeting on screen — completing the
Kotlin → Swift (JNI `.so`) → Swift library chain:

```sh
bazel build --config=android_example \
  //examples/cross_compilation/android_app:app
```

It's packaged with `rules_android` + `rules_kotlin` (dev-only dependencies of
`rules_swift`) and the hermetic `@androidsdk` (no local SDK needed). See
`android_app/README.md`.

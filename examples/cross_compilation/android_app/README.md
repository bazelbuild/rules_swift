# Android app: Kotlin → Swift JNI `.so` → Swift library

A complete, runnable Android app that shows the greeting computed by Swift,
reached over JNI — the application half of the Kotlin → Swift → Swift call chain
that `rules_swift` enables:

```
MainActivity.kt  ──►  NativeBridge.greetingFromSwift()   (Kotlin)
                        │  JNI  (System.loadLibrary("SwiftJNI"))
                        ▼
   //examples/cross_compilation:SwiftJNI   →  libSwiftJNI.so   (swift_binary, linkshared)
     @_cdecl("Java_..._greetingFromSwift")  in SwiftJNI.swift  (Swift)
                        │
                        ▼
   //examples/cross_compilation:Greeter                        (swift_library)
```

## Build & run

```sh
# Build the APK (the flags live in //.bazelrc as `--config=android_example`):
bazel build --config=android_example \
  //examples/cross_compilation/android_app:app

# Install on a connected device/emulator and launch:
adb install -r bazel-bin/examples/cross_compilation/android_app/app.apk
adb shell am start -n com.example.swiftjni/.MainActivity
```

The screen shows **“Hello from Swift, Android!”** — computed by the `Greeter`
`swift_library`, returned through the `@_cdecl` JNI entry point in
`libSwiftJNI.so`, and displayed by Kotlin.

## How it's wired (`BUILD.bazel`)

The APK is built with `rules_android` (`android_binary`) and `rules_kotlin`
(`kt_android_library`) — the real-world way Android apps are packaged. The one
rules_swift-specific detail is getting the prebuilt Swift `.so` into the APK:

- `swift_binary(linkshared = True)` exposes its `.so` via `DefaultInfo`, not
  `CcInfo`, so it can't go straight into `android_binary.deps`. Wrapping it in a
  `cc_library` (a prebuilt `.so` in `srcs` becomes a `CcInfo` dynamic library)
  lets `android_binary`'s per-ABI native split collect it into `lib/arm64-v8a/`.
- `libc++_shared.so` (the NDK's C++ runtime, which the NDK clang links
  dynamically) is selected from the resolved Android cc toolchain by
  rules_swift's `select_android_runtime_lib` and packaged the same way.

The example targets arm64 (`--android_platforms=@rules_android//:arm64-v8a`);
build the `.so` for another ABI and add a matching `cc_library` to support more.

## Dev dependencies

`rules_android` + `rules_kotlin` (and their Maven graph) are **dev-only**
dependencies of `rules_swift` — see the root `MODULE.bazel` (all
`dev_dependency = True`) and the pinned `//:rules_android_maven_install.json`.
They never reach consumers of `rules_swift`; a consumer brings their own Android
rules. The Android SDK is the hermetic `@androidsdk` from
[`hermetic_android_toolchains`](https://github.com/keith/hermetic_android_toolchains)
(no local `$ANDROID_HOME` required).

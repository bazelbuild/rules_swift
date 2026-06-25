# Android app: Kotlin → Swift JNI `.so` → Swift library

A complete, runnable Android app that shows the greeting computed by Swift,
reached over JNI:

```
MainActivity.kt  ──►  NativeBridge.greetingFromSwift()   (Kotlin)
                        │  JNI  (System.loadLibrary("SwiftJNI"))
                        ▼
   :SwiftJNI   →  libSwiftJNI.so   (swift_binary, linkshared)
     @_cdecl("Java_..._greetingFromSwift")  in Sources/SwiftJNI/SwiftJNI.swift
                        │
                        ▼
   :Greeter                                  (swift_library)
```

## Build & run

```sh
bazel build //examples/cross_compilation/android_app:app
adb install -r bazel-bin/examples/cross_compilation/android_app/app.apk
adb shell am start -n com.example.swiftjni/.MainActivity
```

The screen shows **“Hello from Swift, Android!”** — computed by the `Greeter`
`swift_library`, returned through the `@_cdecl` JNI entry point in
`libSwiftJNI.so`, and displayed by Kotlin. (`//.bazelrc` sets
`--android_platforms=@rules_android//:arm64-v8a` and a hermetic JDK.)

## How it's wired (`BUILD.bazel`)

The APK is built with `rules_android` (`android_binary`) and `rules_kotlin`
(`kt_android_library`) — the real-world way Android apps are packaged. The one
rules_swift-specific detail is getting the prebuilt Swift `.so` into the APK:

- `swift_binary(linkshared = True)` exposes its `.so` via `DefaultInfo`, not
  `CcInfo`, so it can't go straight into `android_binary.deps`. Wrapping it in a
  `cc_library` (a prebuilt `.so` in `srcs` becomes a `CcInfo` dynamic library)
  lets `android_binary`'s per-ABI native split collect it into `lib/arm64-v8a/`.
  The split configures the wrapped `swift_binary` for Android, so no explicit
  platform transition is needed.
- `libc++_shared.so` (the NDK's C++ runtime, which the Swift SDK links
  dynamically) is selected from the resolved Android cc toolchain by
  rules_swift's `select_android_runtime_lib` and packaged the same way.

## Dev dependencies

`rules_android` + `rules_kotlin` (and their Maven graph) are **dev-only**
dependencies of `rules_swift`, kept in [`android.MODULE.bazel`](android.MODULE.bazel)
(`include()`d from the root `MODULE.bazel`) with a pinned Maven lock. They never
reach consumers of `rules_swift`; a consumer brings their own Android rules. The
Android SDK is the hermetic `@androidsdk` from
[`hermetic_android_toolchains`](https://github.com/keith/hermetic_android_toolchains)
(no local `$ANDROID_HOME` required).

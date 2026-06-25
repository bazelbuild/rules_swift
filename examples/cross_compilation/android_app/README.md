# Android app: Kotlin → Swift JNI `.so` → Swift library

This directory shows the application half of the
Kotlin → Swift → Swift call chain that `rules_swift` enables:

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

The `rules_swift` side — building `libSwiftJNI.so` from a `swift_binary` that
depends on a normal `swift_library`, and exposing the NDK's `libc++_shared.so`
at a host-independent label — is fully implemented and exercised by
`//examples/cross_compilation:libSwiftJNI.so`.

Packaging that `.so` into an APK is the job of the Android rules
(`rules_android` + `rules_kotlin`) and a local Android SDK. Those are heavy
dependencies (`rules_android` pulls in `rules_go`, `gazelle`, Robolectric, and a
conflicting protobuf), so `rules_swift` deliberately does **not** depend on them;
the APK target lives in *your* module instead. The sources in this directory
(`NativeBridge.kt`, `MainActivity.kt`, `AndroidManifest.xml`) are complete and
ready to drop into such a module.

## `MODULE.bazel` (in your app's module)

```starlark
bazel_dep(name = "rules_swift", version = "...")  # or git_override to this fork
bazel_dep(name = "rules_android", version = "0.7.3")
bazel_dep(name = "rules_kotlin", version = "2.3.20")

swift = use_extension("@rules_swift//swift:extensions.bzl", "swift")
swift.toolchain(name = "swift_toolchain", swift_version = "6.3.2")
swift.android_sdk(toolchain_name = "swift_toolchain")
use_repo(swift, "swift_toolchain")

# One line registers every Swift SDK toolchain (and the standalone host ones).
register_toolchains("@swift_toolchain//:all")

android_sdk = use_extension("@rules_android//rules/android_sdk_repository:rule.bzl", "android_sdk_repository_extension")
use_repo(android_sdk, "androidsdk")
register_toolchains("@androidsdk//:all")
```

Set `ANDROID_HOME` to a local Android SDK (with `platforms;android-34` and a
recent `build-tools`).

## `BUILD.bazel` (in your app's module)

```starlark
load("@rules_android//android:rules.bzl", "android_binary")
load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")

# Lay the Swift JNI library and the NDK C++ runtime out as jniLibs for the
# arm64-v8a ABI. `libSwiftJNI.so` is the swift_binary(linkshared) output;
# `select_android_runtime_lib` selects `libc++_shared.so` from the resolved
# Android cc toolchain (build it under the android platform).
load("@rules_swift//swift/toolchains:android_runtime_lib.bzl", "select_android_runtime_lib")

select_android_runtime_lib(
    name = "libcxx_shared",
    triple = "aarch64-linux-android",
)

genrule(
    name = "jni_libs",
    srcs = [
        "@rules_swift//examples/cross_compilation:libSwiftJNI.so",
        ":libcxx_shared",
    ],
    outs = [
        "lib/arm64-v8a/libSwiftJNI.so",
        "lib/arm64-v8a/libc++_shared.so",
    ],
    cmd = """
        srcs=($(SRCS))
        mkdir -p $(RULEDIR)/lib/arm64-v8a
        cp "$${srcs[0]}" $(RULEDIR)/lib/arm64-v8a/libSwiftJNI.so
        cp "$${srcs[1]}" $(RULEDIR)/lib/arm64-v8a/libc++_shared.so
    """,
)

kt_android_library(
    name = "app_lib",
    srcs = [
        "java/com/example/swiftjni/MainActivity.kt",
        "java/com/example/swiftjni/NativeBridge.kt",
    ],
    manifest = "AndroidManifest.xml",
)

android_binary(
    name = "app",
    manifest = "AndroidManifest.xml",
    custom_package = "com.example.swiftjni",
    # Bundle the native libraries laid out above.
    resource_files = [],
    deps = [":app_lib"],
    # rules_android picks up `lib/<abi>/*.so` produced by the genrule when it is
    # provided as data; depending on your rules_android version you may instead
    # place the .so files under `src/main/jniLibs/<abi>/` or pass them through a
    # `cc_library`/`android_library` `jni_libs` attribute.
    data = [":jni_libs"],
)
```

> The exact mechanism for adding pre-built `.so`s to an `android_binary` varies
> by `rules_android` version; the constant is that `libSwiftJNI.so` and
> `libc++_shared.so` must land under `lib/arm64-v8a/` (and the corresponding
> directory for any other ABIs you build). Build the `.so` for `x86_64` with the
> `//examples/cross_compilation:android-x86_64`-equivalent platform and place it
> under `lib/x86_64/` to support the emulator.

## Building

```sh
# The rules_swift-side artifact (verified by this repo):
bazel build @rules_swift//examples/cross_compilation:libSwiftJNI.so

# The APK (in your module, with the wiring above and ANDROID_HOME set):
bazel build //path/to/android_app:app
```

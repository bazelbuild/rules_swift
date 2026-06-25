# Cross-compilation example (Android)

A complete, runnable Android app that cross-compiles Swift to Android and runs it
through the JNI, built with the Swift SDK toolchain registered by this
repository's `MODULE.bazel` (via the `swift` extension's `android_sdk` tag). See
`doc/standalone_toolchain.md` for the toolchain setup.

Everything lives in [`android_app/`](android_app) — the Swift sources, the Kotlin
app, and the `BUILD.bazel` that packages them into an APK with `rules_android` +
`rules_kotlin`. See [`android_app/README.md`](android_app/README.md).

# Building Swift for Android

A complete, runnable Android app that cross-compiles Swift to Android
and runs it through the JNI. See `doc/standalone_toolchain.md` for the
toolchain setup.

## Build & run

Hermetically:

```sh
bazel run //examples/cross_compilation/android_app:run
```

With a locally installed Android SDK and device:

```sh
bazel build //examples/cross_compilation/android_app:app
adb install -r bazel-bin/examples/cross_compilation/android_app/app.apk
adb shell am start -n com.example.swiftjni/.MainActivity
```

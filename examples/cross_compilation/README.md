# Cross-compilation example (WebAssembly + Android + Static Linux)

Builds plain `swift_library` / `swift_binary` targets for non-host platforms
using the Swift SDK toolchains registered by this repository's `MODULE.bazel`
(via the `swift` extension's `wasm_sdk`, `android_sdk`, and
`static_linux_sdk` tags). See
`doc/standalone_toolchain.md` for the toolchain setup.

All targets are tagged `manual` because they download the Swift SDK bundles
(and, for Android, the NDK) and require the cross toolchains to be registered.

## Targets

| Target | Output | Demonstrates |
|---|---|---|
| `:Greeter` | `.swiftmodule` + `.a` | A normal `swift_library` reused by both entry points below |
| `:Reactor.wasm` | `Reactor.wasm` | A WebAssembly **reactor** (`swift_binary(linkshared)`), no `main`, with exported functions |
| `:web_app` | `web_app/` | A static site embedding `Reactor.wasm`, driven from JS — see [`web/README.md`](web/README.md) |
| `:libSwiftJNI.so` | `libSwiftJNI.so` | An Android **JNI shared library** (`swift_binary(linkshared)`) that calls `:Greeter` |
| `:hello_static_linux` | `hello_static_linux` | A fully static Linux executable targeting `x86_64-swift-linux-musl` |

```sh
# WebAssembly reactor (runnable with wasmtime):
bazel build //examples/cross_compilation:Reactor.wasm
wasmtime run --invoke greeting_length \
    bazel-bin/examples/cross_compilation/Reactor.wasm

# WebAssembly in a browser: a static site that calls the reactor from JS.
bazel build //examples/cross_compilation:web_app
python3 -m http.server -d bazel-bin/examples/cross_compilation/web_app 8000
#   …then open http://localhost:8000  (see web/README.md)

# Android JNI shared library:
bazel build //examples/cross_compilation:libSwiftJNI.so

# Static Linux executable:
bazel build //examples/cross_compilation:hello_static_linux
```

Each `transition_binary` target builds its `swift_binary` under the matching
platform (`:wasm32-wasip1` / `:android-aarch64` /
`:static-linux-x86_64`); you can equivalently pass a platform on the command
line, for example:

* `--platforms=//examples/cross_compilation:wasm32-wasip1`
* `--platforms=//examples/cross_compilation:android-aarch64`
* `--platforms=//examples/cross_compilation:static-linux-x86_64`

## Android app

`android_app/` contains the Kotlin app (and a documented packaging recipe) that
loads `libSwiftJNI.so` and calls into it, completing the
Kotlin → Swift (JNI `.so`) → Swift library chain. Packaging an APK uses
`rules_android` + an Android SDK in the consuming module; see
`android_app/README.md`.

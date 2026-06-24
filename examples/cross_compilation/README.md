# Cross-compilation example (WebAssembly)

Builds plain `swift_library` / `swift_binary` targets for WebAssembly using the
Swift SDK toolchain registered by this repository's `MODULE.bazel` (via the
`swift` extension's `wasm_sdk` tag). See `doc/standalone_toolchain.md` for the
toolchain setup.

All targets are tagged `manual` because they download the Swift SDK bundle and
require the cross toolchain to be registered.

## Targets

| Target | Output | Demonstrates |
|---|---|---|
| `:Greeter` | `.swiftmodule` + `.a` | A normal `swift_library` reused across targets |
| `:Reactor.wasm` | `Reactor.wasm` | A WebAssembly **reactor** (`swift_binary(linkshared)`), no `main`, with exported functions |
| `:web_app` | `web_app/` | A static site embedding `Reactor.wasm`, driven from JS — see [`web/README.md`](web/README.md) |

```sh
# WebAssembly reactor (runnable with wasmtime):
bazel build //examples/cross_compilation:Reactor.wasm
wasmtime run --invoke greeting_length \
    bazel-bin/examples/cross_compilation/Reactor.wasm

# WebAssembly in a browser: a static site that calls the reactor from JS.
bazel build //examples/cross_compilation:web_app
python3 -m http.server -d bazel-bin/examples/cross_compilation/web_app 8000
#   …then open http://localhost:8000  (see web/README.md)
```

`:Reactor.wasm` builds `:Reactor` under the `:wasm32-wasip1` platform; you can
equivalently pass `--platforms=//examples/cross_compilation:wasm32-wasip1` on
the command line.

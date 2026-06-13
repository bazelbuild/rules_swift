# Web app: a Swift WebAssembly reactor in the browser

A tiny static site that embeds `:Reactor.wasm` (a `swift_binary(linkshared =
True)` reactor) and drives it from JavaScript — the page instantiates the
module, runs the WASI reactor's `_initialize`, calls the exported
`greeting_length` / `greeting_into`, reads the string Swift wrote into linear
memory, and displays it.

```sh
# Assemble index.html + Reactor.wasm into one directory.
bazel build //examples/cross_compilation:web_app

# Serve it and open http://localhost:8000 in a browser.
python3 -m http.server -d bazel-bin/examples/cross_compilation/web_app 8000
```

The page shows `“Hello from Swift, WebAssembly!”`.

### Headless check

`verify.mjs` runs the same flow under Node (a minimal WASI shim, no browser), so
the example can be verified in CI / from the command line:

```sh
bazel build //examples/cross_compilation:Reactor.wasm
node examples/cross_compilation/web/verify.mjs \
    bazel-bin/examples/cross_compilation/Reactor.wasm
# -> OK: Swift → WebAssembly greeting verified end-to-end
```

### Notes

- The reactor imports `wasi_snapshot_preview1` for runtime startup; `index.html`
  supplies a minimal shim (success stubs, `random_get` via Web Crypto). A real
  app would use a WASI polyfill such as `@bjorn3/browser_wasi_shim`.
- `linkshared = True` on a wasm target produces a **reactor** (no `_start`); the
  host must call `_initialize()` once before any other export so Swift/C global
  initializers run.
- The output buffer is placed in a freshly `grow`n memory page, avoiding any
  allocator import.

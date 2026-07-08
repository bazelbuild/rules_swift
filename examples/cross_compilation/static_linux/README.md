# Building Swift for Static Linux

A simple executable that cross-compiles Swift to a fully static musl binary with
the Static Linux Swift SDK. See `doc/standalone_toolchain.md` for the toolchain
setup.

## Build

```sh
bazel build //examples/cross_compilation/static_linux:hello_static_linux
```

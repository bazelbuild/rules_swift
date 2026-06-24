// Headless end-to-end check of the WebAssembly reactor, mirroring index.html:
// instantiate with a minimal WASI shim, run `_initialize`, then read the
// greeting that Swift writes into linear memory. Exits non-zero on mismatch.
//
//   node examples/cross_compilation/web/verify.mjs \
//       bazel-bin/examples/cross_compilation/Reactor.wasm
//
// (index.html does exactly this in a browser.)

import { readFileSync } from "node:fs";
import { webcrypto as crypto } from "node:crypto";

const wasmPath = process.argv[2] ?? "bazel-bin/examples/cross_compilation/Reactor.wasm";
const expected = "Hello from Swift, WebAssembly!";

let instance;
const dv = () => new DataView(instance.exports.memory.buffer);
const u8 = () => new Uint8Array(instance.exports.memory.buffer);
const SUCCESS = 0, BADF = 8;
const wasi = {
  args_sizes_get: (a, b) => { dv().setUint32(a, 0, true); dv().setUint32(b, 0, true); return SUCCESS; },
  args_get: () => SUCCESS,
  environ_sizes_get: (a, b) => { dv().setUint32(a, 0, true); dv().setUint32(b, 0, true); return SUCCESS; },
  environ_get: () => SUCCESS,
  fd_fdstat_get: (fd, ptr) => { for (let i = 0; i < 24; i++) dv().setUint8(ptr + i, 0); return SUCCESS; },
  fd_prestat_get: () => BADF,
  fd_prestat_dir_name: () => BADF,
  fd_close: () => SUCCESS,
  fd_read: (fd, iovs, n, nread) => { dv().setUint32(nread, 0, true); return SUCCESS; },
  fd_seek: (fd, off, whence, newOff) => { dv().setUint32(newOff, 0, true); return SUCCESS; },
  fd_write: (fd, iovs, n, nwritten) => {
    let written = 0;
    for (let i = 0; i < n; i++) written += dv().getUint32(iovs + i * 8 + 4, true);
    dv().setUint32(nwritten, written, true);
    return SUCCESS;
  },
  path_open: () => BADF,
  proc_exit: (code) => { throw new Error("proc_exit(" + code + ")"); },
  random_get: (ptr, len) => { crypto.getRandomValues(u8().subarray(ptr, ptr + len)); return SUCCESS; },
};

const bytes = readFileSync(wasmPath);
instance = (await WebAssembly.instantiate(bytes, { wasi_snapshot_preview1: wasi })).instance;
instance.exports._initialize();

const length = instance.exports.greeting_length();
const memory = instance.exports.memory;
const ptr = memory.buffer.byteLength;
memory.grow(Math.ceil((length + 1) / 65536));
const written = instance.exports.greeting_into(ptr, length + 1);
const greeting = new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, written));

console.log("greeting:", JSON.stringify(greeting));
if (greeting !== expected) {
  console.error(`FAIL: expected ${JSON.stringify(expected)}`);
  process.exit(1);
}
console.log("OK: Swift → WebAssembly greeting verified end-to-end");

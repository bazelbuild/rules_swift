import Greeter

// A WebAssembly "reactor" module: it has no `main`/entry point. Instead it
// exports functions that a host (e.g. JavaScript via `WebAssembly.instantiate`)
// calls after instantiation. The `@_cdecl` attribute gives each function a
// plain C name; the linker still needs `--export=` (passed via `linkopts` in
// the BUILD file) to keep them in the final module.

/// Writes the greeting into `buffer` (NUL-terminated, truncated to `capacity`)
/// and returns the number of bytes written, excluding the terminator.
@_cdecl("greeting_into")
public func greeting_into(_ buffer: UnsafeMutablePointer<CChar>, _ capacity: Int32) -> Int32 {
  let message = Greeter(subject: "WebAssembly").greeting()
  let bytes = Array(message.utf8)
  let limit = min(bytes.count, Int(capacity) - 1)
  for index in 0 ..< limit {
    buffer[index] = CChar(bitPattern: bytes[index])
  }
  buffer[limit] = 0
  return Int32(limit)
}

/// Returns the length the greeting would occupy (so the host can size a buffer).
@_cdecl("greeting_length")
public func greeting_length() -> Int32 {
  return Int32(Greeter(subject: "WebAssembly").greeting().utf8.count)
}

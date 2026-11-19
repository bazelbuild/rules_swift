import examples_cross_compilation_android_app_CxxGreeter
import CxxStdlib

// C++ interop: libc++ headers through the SDK's clang resource directory, and
// swiftCxx, swiftCxxStdlib and the static libc++ at link time.
public func cxxGreeting(subject: String) -> String {
  return String(cxxGreeting(std.string(subject)))
}

// A trivial JNI entry point used by the Android toolchain analysis tests. The
// raw-pointer parameters and `Int32` return keep it free of any platform-
// specific JNI module import, so it builds for Android with only the SDK
// toolchain registered.
@_cdecl("Java_com_example_Fixture_value")
public func value(
  _: UnsafeMutableRawPointer?,
  _: UnsafeMutableRawPointer?
) -> Int32 {
  return 42
}

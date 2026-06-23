import Android
import Greeter

// The JNI entry point, written entirely in Swift. `import Android` provides the
// JNI types (`JNIEnv`, `jclass`, `jstring`, ...) from the Android Swift SDK, so
// no C shim is needed. `@_cdecl` gives the function the exact symbol name JNI
// looks up: `Java_<package>_<class>_<method>`, with `.`/`_` escaped per the JNI
// spec. It is the Kotlin-callable native implementation of:
//
//   package com.example.swiftjni
//   class NativeBridge { external fun greetingFromSwift(): String }
//
// and it delegates to the `Greeter` `swift_library` (a normal dependency),
// completing the Kotlin -> Swift (JNI .so) -> Swift library call chain.
@_cdecl("Java_com_example_swiftjni_NativeBridge_greetingFromSwift")
public func greetingFromSwift(
  _ env: UnsafeMutablePointer<JNIEnv?>,
  _ clazz: jclass
) -> jstring? {
  let message = Greeter(subject: "Android").greeting()
  return message.withCString { cString in
    env.pointee!.pointee.NewStringUTF(env, cString)
  }
}

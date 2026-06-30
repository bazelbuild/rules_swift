import Android
import Greeter

// The JNI entry point, written entirely in Swift: `import Android` provides the
// JNI types, and `@_cdecl` gives the function the `Java_<package>_<class>_<method>`
// symbol name that `NativeBridge.greetingFromSwift()` binds to.
@_cdecl("Java_com_example_swiftjni_NativeBridge_greetingFromSwift")
public func greetingFromSwift(_ env: UnsafeMutablePointer<JNIEnv?>, _ clazz: jclass) -> jstring? {
  let message = Greeter(subject: "Android").greeting()
  return message.withCString { cString in
    env.pointee!.pointee.NewStringUTF(env, cString)
  }
}

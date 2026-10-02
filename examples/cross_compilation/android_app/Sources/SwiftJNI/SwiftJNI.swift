import Android
import Greeter

@available(Android 33, *)
private func captureBacktrace() {
  withUnsafeTemporaryAllocation(of: UnsafeMutableRawPointer.self, capacity: 1) { address in
    _ = Android.backtrace(address.baseAddress!, 1)
  }
}

// The JNI entry point, written entirely in Swift: `import Android` provides the
// JNI types, and `@_cdecl` gives the function the `Java_<package>_<class>_<method>`
// symbol name that `NativeBridge.greetingFromSwift()` binds to.
@_cdecl("Java_com_example_swiftjni_NativeBridge_greetingFromSwift")
public func greetingFromSwift(_ env: UnsafeMutablePointer<JNIEnv?>, _ clazz: jclass) -> jstring? {
  // The app supports API 28, but backtrace is only available on API 33+.
  if #available(Android 33, *) {
    captureBacktrace()
  }

  // Exercise Swift Concurrency so the example links (and runs) the async
  // runtime — see Greeter.greetingAsync().
  Task {
    _ = await Greeter(subject: "Android").greetingAsync()
  }
  let message = Greeter(subject: "Android").greeting()
  return message.withCString { cString in
    env.pointee!.pointee.NewStringUTF(env, cString)
  }
}

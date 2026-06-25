package com.example.swiftjni

/**
 * Loads the Swift JNI shared library (`libSwiftJNI.so`, built by the
 * `//examples/cross_compilation:SwiftJNI` `swift_binary(linkshared = True)`)
 * and exposes its Swift entry point to Kotlin.
 *
 * The native method binds by name to the Swift `@_cdecl` function
 * `Java_com_example_swiftjni_NativeBridge_greetingFromSwift`, which in turn
 * calls the `Greeter` `swift_library` — completing the
 * Kotlin -> Swift (in the `.so`) -> Swift library call chain.
 */
object NativeBridge {
  init {
    System.loadLibrary("SwiftJNI")
  }

  external fun greetingFromSwift(): String
}

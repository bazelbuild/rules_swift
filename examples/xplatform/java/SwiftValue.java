package com.example.swiftjni;

final class SwiftValue {
  private SwiftValue() {}

  static int value() {
    return nativeValue();
  }

  private static native int nativeValue();
}

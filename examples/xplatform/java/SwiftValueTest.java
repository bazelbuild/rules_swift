package com.example.swiftjni;

import java.nio.file.Paths;

public final class SwiftValueTest {
  private static final int EXPECTED_VALUE = 42;

  public static void main(String[] args) throws Exception {
    if (args.length != 1) {
      throw new IllegalArgumentException("Expected exactly one native library path argument");
    }

    System.load(Paths.get(args[0]).toAbsolutePath().toString());

    int actual = SwiftValue.value();
    if (actual != EXPECTED_VALUE) {
      throw new AssertionError("Expected " + EXPECTED_VALUE + ", got " + actual);
    }
  }
}

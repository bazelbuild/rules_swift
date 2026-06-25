package com.example.swiftjni.kotlin

import java.nio.file.Paths

private const val EXPECTED_VALUE = 42

fun main(args: Array<String>) {
  require(args.size == 1) { "Expected exactly one native library path argument" }

  System.load(Paths.get(args[0]).toAbsolutePath().toString())

  val actual = nativeValue()
  check(actual == EXPECTED_VALUE) { "Expected $EXPECTED_VALUE, got $actual" }
}

private external fun nativeValue(): Int

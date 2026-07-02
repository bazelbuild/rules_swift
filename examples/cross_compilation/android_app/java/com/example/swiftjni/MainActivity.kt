package com.example.swiftjni

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

/** Displays the greeting computed by Swift, reached via JNI. */
class MainActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val textView = TextView(this)
    textView.text = NativeBridge.greetingFromSwift()
    setContentView(textView)
  }
}

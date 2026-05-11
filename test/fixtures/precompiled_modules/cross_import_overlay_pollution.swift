import AppKit
import Testing

private func foo() {
  let image = NSImage(data: Data())!
  // This currently relies on a protocol conformance for NSImage that exists in _Testing_AppKit which is
  // imported implicitly through a cross import overlay
  Attachment.record(image, named: "foo", as: .png)
}

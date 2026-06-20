import ExtensionUnavailableObjC
import Foundation

@available(macOSApplicationExtension, unavailable)
private func foo() { // expected-note {{'foo()' has been explicitly marked unavailable here}}
    print("This is a private function in the application extension library.")
}

let applicationExtensionCheck: Void = foo() // expected-error {{'foo()' is unavailable in application extensions for macOS}}
let objcApplicationExtensionCheck: String = ExtensionUnavailableAPI.extensionUnavailableMessage() // expected-error {{is unavailable in application extensions for macOS: message}}

import Foundation

@objc public class MixedLibSwift: NSObject {
    @objc public func callObjC() {
        let lib = MixedLib()
        lib.doSomething()
    }
}

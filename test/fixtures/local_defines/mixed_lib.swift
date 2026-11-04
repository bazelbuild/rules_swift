import Foundation

#if !LOCAL_FOO
  #error("LOCAL_FOO should be defined")
#endif
#if !PROPAGATED_BAR
  #error("PROPAGATED_BAR should be defined")
#endif

@objc public class MixedLibSwift: NSObject {
    @objc public func callObjC() {
        let lib = MixedLib()
        lib.doSomething()
    }
}

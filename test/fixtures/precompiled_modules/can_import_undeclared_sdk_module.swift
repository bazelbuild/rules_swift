#if canImport(SwiftUI)
// #error("should this be false if the dep is missing?")
import SwiftUI
#endif

public struct CanImportUndeclaredSDKModule {
    public init() {}
}

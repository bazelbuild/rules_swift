import Foundation

public enum MixedGreeterSwift {
    public static func combinedGreeting() -> String {
        return "Swift+\(MixedGreeterObjC.objcGreeting())"
    }
}

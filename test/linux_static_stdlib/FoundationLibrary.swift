import Foundation

public func swiftOrgHost() -> String {
    URL(string: "https://www.swift.org")!.host()!
}

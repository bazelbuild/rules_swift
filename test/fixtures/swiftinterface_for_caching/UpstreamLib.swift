public struct UpstreamGreeting {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public func message() -> String {
        return "Hello, \(name)!"
    }
}

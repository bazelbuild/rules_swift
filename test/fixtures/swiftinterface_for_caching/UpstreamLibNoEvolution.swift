public struct UpstreamCounter {
    public private(set) var count: Int

    public init() {
        self.count = 0
    }

    public mutating func advance() {
        count += 1
    }
}

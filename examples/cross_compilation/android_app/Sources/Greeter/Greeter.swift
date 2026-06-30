public struct Greeter {
  private let subject: String

  public init(subject: String) {
    self.subject = subject
  }

  public func greeting() -> String {
    return "Hello from Swift, \(subject)!"
  }
}

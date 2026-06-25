/// A plain `swift_library` used as a normal dependency of the Android JNI
/// entry point. Nothing in here is platform-specific; it is compiled for
/// whichever platform the depending target is built for.
public struct Greeter {
  private let subject: String

  public init(subject: String) {
    self.subject = subject
  }

  public func greeting() -> String {
    return "Hello from Swift, \(subject)!"
  }
}

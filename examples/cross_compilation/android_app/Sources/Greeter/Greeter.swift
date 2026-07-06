public struct Greeter {
  private let subject: String

  public init(subject: String) {
    self.subject = subject
  }

  public func greeting() -> String {
    return "Hello from Swift, \(subject)!"
  }

  // Swift Concurrency: async code pulls in the concurrency runtime, whose
  // global executor lives on libdispatch. This exists so the example is a
  // link-time regression test for the `-ldispatch -lBlocksRuntime` linkopts
  // in the generated Android toolchain — without them, linking any `async`
  // Swift fails with `undefined symbol: dispatch_main` (and friends).
  public func greetingAsync() async -> String {
    return greeting()
  }
}

// Import the C++ interface.
@_exported import CxxCounter

/// Wraps the C++ interface in a Swift interface.
extension swiftexample.Counter {

  mutating public func Decrement() {
    count_ = count_ - 1
  }

}

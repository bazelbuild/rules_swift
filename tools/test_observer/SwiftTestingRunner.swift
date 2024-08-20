// Copyright 2024 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#else
  #error("Unsupported platform")
#endif

/// A test runner that runs tests discovered by the swift-testing framework.
public final class SwiftTestingRunner: Sendable {
  /// A wrapper around a swift-testing test identifier used by the test collector.
  private struct Test: Testable {
    /// The identifier of the test.
    let testIdentifier: String
  }

  /// A test or suite discovered by the swift-testing framework.
  private enum TestOrSuite {
    case suite(String)
    case test(Test)
  }

  /// Discovers and runs the tests.
  public static func run() async throws {
    guard let entryPoint = SwiftTestingEntryPoint() else {
      // The entry point wasn't found, meaning swift-testing wasn't linked in and there are
      // no tests to run. This is not an error.
      return
    }
    try await SwiftTestingRunner(entryPoint: entryPoint).run()
  }

  /// The JSON ABI entry point of the swift-testing framework.
  private let entryPoint: SwiftTestingEntryPoint

  /// A set consisting only of the test suites that are discovered.
  private let discoveredSuites: Locked<Set<String>> = .init([])

  /// Creates a new runner that will use the given entry point to communicate with the
  /// swift-testing framework.
  private init(entryPoint: SwiftTestingEntryPoint) {
    self.entryPoint = entryPoint
  }

  /// Discovers and runs the tests.
  private func run() async throws {
    var collector = try ShardingFilteringTestCollector<Test>()
    let selectedTests: [Test]?

    // We have to do this even when we're not sharding to filtering because we need to know which of
    // the tests are actually suites (so that we don't include them in our xUnit results).
    for try await testOrSuite in try await listTests() {
      switch testOrSuite {
      case .suite(let suiteID):
        discoveredSuites.withLock { $0.insert(suiteID) }
      case .test(let test):
        collector.addTest(test)
      }
    }
    if collector.willShardOrFilter {
      selectedTests = collector.testsInCurrentShard
    } else {
      selectedTests = nil
    }

    // Run the tests in the current shard.
    try await runTests(selectedTests: selectedTests)
  }

  /// Returns an async stream of values representing the tests and suites discovered in the binary
  /// by the swift-testing framework.
  private func listTests() async throws -> AsyncThrowingStream<TestOrSuite, Error> {
    let listTestsConfiguration: JSON = [
      "listTests": true,
      "verbosity": .number(Int.min),  // Don't print anything to stdout.
    ]

    // All of this could really just be a simple `.compactMap` on the stream and we'd return an
    // opaque type, but primary associated types on `AsyncSequence` aren't usable before the runtime
    // included with macOS 15.0. See SE-0421 for details
    // (https://github.com/swiftlang/swift-evolution/blob/main/proposals/0421-generalize-async-sequence.md).
    var escapedContinuation: AsyncThrowingStream<TestOrSuite, Error>.Continuation? = nil
    let stream = AsyncThrowingStream(TestOrSuite.self, bufferingPolicy: .unbounded) {
      continuation in escapedContinuation = continuation
    }
    guard let escapedContinuation else {
      preconditionFailure("Stream continuation was never set")
    }
    do {
      for try await recordJSON in try await entryPoint(configuration: listTestsConfiguration) {
        guard
          case .object(let record) = recordJSON,
          case .object(let payload) = record["payload"],
          case .string(let id) = payload["id"]
        else {
          continue
        }
        switch payload["kind"] {
        case .string("function"):
          escapedContinuation.yield(.test(Test(testIdentifier: id)))
        case .string("suite"):
          escapedContinuation.yield(.suite(id))
        default:
          continue
        }
      }
      escapedContinuation.finish()
    } catch {
      escapedContinuation.finish(throwing: error)
    }
    return stream
  }

  /// Runs the given list of tests (or all tests).
  ///
  /// - Parameter selectedTests: If this parameter is not nil, only the given list of tests will be
  ///   run by passing them as filters to the entry point. If nil, all tests will be run.
  private func runTests(selectedTests: [Test]?) async throws {
    var runTestsConfiguration: [String: JSON] = [:]
    if let selectedTests {
      runTestsConfiguration["filter"] = .array(
        selectedTests.map {
          JSON.string(NSRegularExpression.escapedPattern(for: $0.testIdentifier))
        })
    }
    for try await recordJSON in try await entryPoint(configuration: .object(runTestsConfiguration))
    {
      guard case .object(let record) = recordJSON,
        case .string("event") = record["kind"],
        case .object(let payload) = record["payload"]
      else {
        continue
      }
      recordEvent(payload)
    }
  }

  private func recordEvent(_ payload: [String: JSON]) {
    // We only care about test events that have a test ID and an instant (when they occurred).
    guard
      case .string(let kind) = payload["kind"],
      case .string(let testID) = payload["testID"],
      // Ignore suites. The xUnit recorder reconstructs the hierarchy.
      !discoveredSuites.withLock { $0.contains(testID) },
      case .object(let instantJSON) = payload["instant"],
      case .number(let absolute) = instantJSON["absolute"]
    else {
      return
    }
    let instant = EncodedInstant(seconds: absolute.doubleValue)
    let nameComponents = nameComponents(for: testID)

    switch kind {
    case "testStarted":
      XUnitTestRecorder.shared.recordTestStarted(nameComponents: nameComponents, time: instant)

    case "testEnded":
      XUnitTestRecorder.shared.recordTestEnded(nameComponents: nameComponents, time: instant)

    case "issueRecorded":
      guard
        case .array(let messages) = payload["messages"],
        // Don't record known issues.
        case .object(let issue) = payload["issue"],
        case .bool(false) = issue["isKnown"]
      else {
        return
      }
      // The issue may have multiple messages, some of which are extra details. Pick out the main
      // message for the failure.
      // TODO: b/301468828 - Handle the extra detail messages as well.
      for case .object(let message) in messages {
        guard
          case .string("fail") = message["symbol"],
          case .string(let text) = message["text"]
        else {
          return
        }
        XUnitTestRecorder.shared.recordTestIssue(
          nameComponents: nameComponents,
          issue: RecordedIssue(kind: .failure, reason: text))
      }

    default:
      break
    }
  }

  /// Returns a list of name components by parsing the given test identifier.
  private func nameComponents(for testID: String) -> [String] {
    let components = testID.split(separator: "/")
    // Some test IDs end with the source location of the test, which is not typically useful to show
    // as part of the hierarchy.
    if let last = components.last, last.firstMatch(of: /\.swift:\d+:\d+/) != nil {
      return components[..<(components.count - 1)].map(String.init)
    }
    return components.map(String.init)
  }
}

/// Represents an instant in time that is encoded as part of a test event.
///
/// The instant is encoded as a double representing the number of seconds retrieved from
/// `SuspendingClock` at the time the event occurred. We can't reconstitute that value back into a
/// `SuspendingClock.Instant`, but they're all relative to each other so we can provide our own
/// `InstantProtocol` implementation that is used to compute the duration between two events.
private struct EncodedInstant: Comparable, InstantProtocol {
  /// The number of seconds since the test clock's basis.
  var seconds: Double

  static func < (lhs: EncodedInstant, rhs: EncodedInstant) -> Bool {
    return lhs.seconds < rhs.seconds
  }

  func advanced(by duration: Swift.Duration) -> EncodedInstant {
    let components = duration.components
    return EncodedInstant(
      seconds: seconds + Double(components.seconds) + Double(components.attoseconds) / 1e18)
  }

  func duration(to other: EncodedInstant) -> Swift.Duration {
    return .seconds(other.seconds - self.seconds)
  }
}

/// Represents the entry point of the swift-testing framework and handles the translation of
/// requests and responses between structured JSON and raw byte buffers.
private struct SwiftTestingEntryPoint {
  private typealias ABIv0EntryPoint = @convention(thin) @Sendable (
    _ configurationJSON: UnsafeRawBufferPointer?,
    _ recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
  ) async throws -> Bool

  private let entryPoint: ABIv0EntryPoint

  /// Creates the entry point by looking it up by name in the current process, or fails if the
  /// entry point is not found.
  init?() {
    guard let entryPointRaw = dlsym(rtldDefault, "swt_abiv0_getEntryPoint") else {
      return nil
    }
    let abiv0_getEntryPoint = unsafeBitCast(
      entryPointRaw, to: (@convention(c) () -> UnsafeRawPointer).self)
    self.entryPoint = unsafeBitCast(abiv0_getEntryPoint(), to: ABIv0EntryPoint.self)
  }

  /// Calls the entry point with the given configuration JSON and returns an asynchronous stream of
  /// the JSON records that the framework produces as a response.
  func callAsFunction(
    configuration configurationJSON: JSON
  ) async throws -> AsyncThrowingStream<JSON, Error> {
    // Since `withUnsafeBytes` is not `async`, we have to copy the data out into a separate
    // buffer and then invoke the entry point.
    let configurationJSONBytes = try configurationJSON.encodedData.withUnsafeBytes { bytes in
      let result = UnsafeMutableRawBufferPointer.allocate(byteCount: bytes.count, alignment: 1)
      result.copyMemory(from: bytes)
      return result
    }
    defer { configurationJSONBytes.deallocate() }

    // `Async(Throwing)Stream` is explicitly designed to allow its continuation to escape. We have
    // to do this since the entry point function that we're calling is `async`, but the closure
    // passed to the stream's initializer is not allowed to be `async`.
    var escapedContinuation: AsyncThrowingStream<JSON, Error>.Continuation? = nil
    let stream = AsyncThrowingStream(JSON.self, bufferingPolicy: .unbounded) { continuation in
      escapedContinuation = continuation
    }
    guard let escapedContinuation else {
      preconditionFailure("Stream continuation was never set")
    }
    do {
      _ = try await self.entryPoint(UnsafeRawBufferPointer(configurationJSONBytes)) {
        recordJSONBytes in
        let data = Data(bytes: recordJSONBytes.baseAddress!, count: recordJSONBytes.count)
        do {
          let json = try JSON(byDecoding: data)
          escapedContinuation.yield(json)
        } catch {
          escapedContinuation.finish(throwing: error)
        }
      }
      escapedContinuation.finish()
    } catch {
      escapedContinuation.finish(throwing: error)
    }
    return stream
  }
}

// `RTLD_DEFAULT` is only defined on Linux when `_GNU_SOURCE` is defined. Just redefine it
// here for convenience.
#if compiler(>=5.10)
  #if os(Linux)
    private nonisolated(unsafe) let rtldDefault = UnsafeMutableRawPointer(bitPattern: 0)
  #else
    private nonisolated(unsafe) let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
  #endif
#else
  #if os(Linux)
    private let rtldDefault = UnsafeMutableRawPointer(bitPattern: 0)
  #else
    private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
  #endif
#endif

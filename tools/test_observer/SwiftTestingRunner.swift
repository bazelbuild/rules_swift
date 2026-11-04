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
#elseif canImport(WinSDK)
  import WinSDK
#else
  #error("Unsupported platform")
#endif

/// A test runner that runs tests discovered by the swift-testing framework.
public final class SwiftTestingRunner: Sendable {
  /// A wrapper around a swift-testing test identifier used by the test collector.
  private struct Test: Testable {
    /// The identifier of the test.
    let testIdentifier: String

    init(testIdentifier: String) {
      // The test identifier given by swift-testing starts with the name of the module, which we
      // strip off because it isn't terribly useful for filtering -- it's burdensome for users to
      // type and IDEs cannot easily determine it without querying the build system.
      let components = testIdentifier.split(separator: ".", maxSplits: 1)
      if components.count > 1 {
        self.testIdentifier = String(components[1])
      } else {
        self.testIdentifier = testIdentifier
      }
    }
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
        discoveredSuites.withLock { discoveredSuites in
          _ = discoveredSuites.insert(suiteID)
        }
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
      // If we applied a test filter and no tests were selected, setting the `filter` configuration
      // value to an empty array will be treated by the runner as if there were no filter (and thus
      // run *all* tests). To handle this correctly, we ask the runner to explicitly skip all tests.
      if selectedTests.isEmpty {
        runTestsConfiguration["skip"] = [".*"]
      } else {
        runTestsConfiguration["filter"] = .array(
          selectedTests.map {
            JSON.string(NSRegularExpression.escapedPattern(for: $0.testIdentifier))
          })
      }
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
      case .string(let testID) = payload["testID"]
    else {
      return
    }

    // Ignore suites. The xUnit recorder reconstructs the hierarchy.
    let isDiscoveredSuite = discoveredSuites.withLock { discoveredSuites in
      discoveredSuites.contains(testID)
    }
    guard
      !isDiscoveredSuite,
      case .object(let instantJSON) = payload["instant"],
      case .number(let absolute) = instantJSON["absolute"]
    else {
      return
    }
    let instant = TestInstant(seconds: absolute.doubleValue)
    let nameComponents = nameComponents(for: testID)

    // Later versions of swift-testing (after Xcode 16.0) stopped reporting suites that don't use
    // the `@Suite` attribute in the `listTests` request
    // (https://github.com/swiftlang/swift-testing/issues/1099). It's not clear if this is
    // intentional or not, but we still need to be able to distinguish suites from test functions to
    // produce the correct tree structure in the test recorder. We can distinguish them by observing
    // that the last component of a test function ID (after the source location is stripped off, as
    // `nameComponents` does above) will have trailing parentheses, while suites will just be the
    // name of the type.
    guard let last = nameComponents.last, last.hasSuffix(")") else {
      return
    }

    switch kind {
    case "testStarted":
      XUnitTestRecorder.shared.recordTestStarted(nameComponents: nameComponents, time: instant)

    case "testEnded":
      XUnitTestRecorder.shared.recordTestEnded(nameComponents: nameComponents, time: instant)

    case "issueRecorded":
      guard
        case .object(let issue) = payload["issue"],
        !SwiftTestingRunner.isKnownIssue(issue),
        SwiftTestingRunner.isFailingIssue(issue)
      else {
        return
      }
      XUnitTestRecorder.shared.recordTestIssue(
        nameComponents: nameComponents,
        issue: RecordedIssue(kind: .failure, reason: SwiftTestingRunner.failureReason(for: payload)))

    default:
      break
    }
  }

  /// Returns a value indicating whether the given encoded issue is a known issue (i.e., one that
  /// was recorded inside `withKnownIssue` and therefore should not fail the test).
  ///
  /// Before version 6.5 of the JSON event stream schema, `isKnown` was a required boolean. In 6.5
  /// (https://github.com/swiftlang/swift-testing/pull/1839), it became optional: it is omitted
  /// entirely when the issue is not known, and it may be the known issue's comment string instead
  /// of `true`. Only an explicit `true` or a comment string counts as known; treating a missing
  /// field as known would silently drop every failure.
  public static func isKnownIssue(_ issue: [String: JSON]) -> Bool {
    switch issue["isKnown"] {
    case .bool(let isKnown):
      return isKnown
    case .string:
      return true
    default:
      return false
    }
  }

  /// Returns a value indicating whether the given encoded issue should fail the test.
  ///
  /// `isFailure` was added in version 6.3 of the JSON event stream schema (alongside warning
  /// severities). Earlier schemas only had failing issues, so a missing field means the issue fails.
  public static func isFailingIssue(_ issue: [String: JSON]) -> Bool {
    if case .bool(let isFailure) = issue["isFailure"] {
      return isFailure
    }
    return true
  }

  /// Returns a human-readable description of the issue in the given `issueRecorded` event payload.
  ///
  /// Schemas before 6.5 include a `messages` array containing the same text that swift-testing
  /// prints to the console, and we use its `fail` message when present. Starting with 6.5,
  /// `messages` is omitted unless the `SWIFT_TESTING_EVENT_STREAM_MESSAGES_FIELD_ENABLED`
  /// environment variable is set, so we build an equivalent description from the structured
  /// `issue`, `sourceLocation`, and `comments` fields instead.
  public static func failureReason(for payload: [String: JSON]) -> String {
    if case .array(let messages) = payload["messages"] {
      for case .object(let message) in messages {
        if case .string("fail") = message["symbol"], case .string(let text) = message["text"] {
          return text
        }
      }
    }

    var reason = "Issue recorded"
    if case .object(let location) = payload["sourceLocation"],
      case .string(let filePath) = location["filePath"] ?? location["fileID"],
      case .number(let line) = location["line"],
      case .number(let column) = location["column"]
    {
      let fileName = filePath.split(separator: "/").last.map(String.init) ?? filePath
      reason += " at \(fileName):\(line.intValue):\(column.intValue)"
    }

    if case .object(let issue) = payload["issue"] {
      if case .object(let expression) = issue["expression"],
        case .string(let sourceCode) = expression["sourceCode"]
      {
        reason += ": Expectation failed: \(sourceCode)"
      } else if case .object(let error) = issue["error"],
        case .string(let description) = error["description"]
      {
        reason += ": Caught error: \(description)"
      } else if case .number(let timeLimit) = issue["exceededTimeLimit"] {
        reason += ": Time limit was exceeded: \(timeLimit.doubleValue) seconds"
      }
    }

    if case .array(let comments) = payload["comments"] {
      for case .string(let comment) in comments {
        reason += " - \(comment)"
      }
    }
    return reason
  }

  /// Matches the trailing source location that swift-testing appends to some test IDs.
  ///
  /// `NSRegularExpression` rather than a regex literal: literals require the `Regex` runtime, which
  /// is only available on iOS 16, macOS 13 and later, and this tool is linked into every
  /// `swift_test` binary regardless of deployment target.
  private static let sourceLocationSuffix = try! NSRegularExpression(
    pattern: #"\.swift:\d+:\d+"#)

  /// Returns a list of name components by parsing the given test identifier.
  private func nameComponents(for testID: String) -> [String] {
    let components = testID.split(separator: "/")
    // Some test IDs end with the source location of the test, which is not typically useful to show
    // as part of the hierarchy.
    if let last = components.last {
      let lastString = String(last)
      let range = NSRange(lastString.startIndex..., in: lastString)
      if Self.sourceLocationSuffix.firstMatch(in: lastString, range: range) != nil {
        return components[..<(components.count - 1)].map(String.init)
      }
    }
    return components.map(String.init)
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
    guard let entryPointRaw = _loadSwiftTestingSymbol("swt_abiv0_getEntryPoint") else {
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

/// Looks up a symbol exported by the swift-testing framework in the current process, returning
/// `nil` if it is not present (i.e. swift-testing was not linked into the test binary).
#if canImport(WinSDK)
  private func _loadSwiftTestingSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    // `GetProcAddress` resolves a symbol from a specific module, so check the modules that may
    // export the swift-testing ABI: the test executable itself (when statically linked) and the
    // `Testing.dll` shared library.
    let modules: [HMODULE?] = [
      GetModuleHandleW(nil),
      "Testing.dll".withCString(encodedAs: UTF16.self) { GetModuleHandleW($0) },
    ]
    for module in modules {
      guard let module else { continue }
      if let symbol = name.withCString({ GetProcAddress(module, $0) }) {
        return unsafeBitCast(symbol, to: UnsafeMutableRawPointer.self)
      }
    }
    return nil
  }
#else
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

  private func _loadSwiftTestingSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    return dlsym(rtldDefault, name)
  }
#endif

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

import Dispatch
import Foundation

/// An issue that occurred during a test.
public struct RecordedIssue: Sendable {
  /// The kind of issue that occurred.
  public enum Kind: String, Sendable {
    case failure
    case error
    case skipped
  }

  /// The kind of issue that occurred.
  public var kind: Kind

  /// A descriptive message that explains the issue.
  public var reason: String

  public init(kind: Kind, reason: String) {
    self.kind = kind
    self.reason = reason
  }
}

/// A recorder for test events that is agnostic to the test framework but emits output using the
/// [xUnit/JUnit test result schema](https://windyroad.com.au/dl/Open%20Source/JUnit.xsd).
///
/// This recorder treats tests as a tree structure, where tests occur at leaf nodes and those leaves
/// contain timing data and issues recorded during the test. This allows us to support both XCTest
/// tests (where each path through the tree is of length two -- the class name, then the test name)
/// as well as swift-testing (which supports top-level tests outside of suites and also arbitrarily
/// nested suites).
///
/// In an async-first world, it would make sense to make this an actor instead of using manual
/// locking. However, since XCTest delivers its events in a synchronous context, it's easier to use
/// old-fashioned locking.
public final class XUnitTestRecorder: Sendable {
  /// Context that is mutated by the test reader, protected by a lock.
  private struct Context: Sendable {
    /// The total number of tests that have run.
    var testCount: Int = 0

    /// A tree structure that contains all of the test results.
    var testData: TestTree = .init()

    /// Indicates whether any failures have been recorded.
    var hasFailure: Bool = false
  }

  /// The shared instance of the recorder.
  public static let shared = XUnitTestRecorder()

  /// The context that is mutated by the test reader, protected by a lock.
  private let context: Locked<Context> = Locked(.init())

  /// Indicates whether any tests have run.
  public var didTestsRun: Bool {
    context.withLock { context in
      context.testCount > 0
    }
  }

  /// Indicates whether any failures have been recorded.
  public var hasFailure: Bool {
    context.withLock { context in
      context.hasFailure
    }
  }

  /// The total number of tests that have run.
  public var testCount: Int {
    context.withLock { context in
      context.testCount
    }
  }

  /// Writes the test results to the XML output file dictated by the environment variable passed by
  /// Bazel.
  public func writeXML() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["XML_OUTPUT_FILE"] else {
      return
    }
    let output = context.withLock { context in
      var output = #"""
        <?xml version="1.0" encoding="utf-8"?>
        <testsuites>

        """#

      writeTestTree(context.testData, indentation: "  ", to: &output)

      output += #"""
        </testsuites>

        """#
      return output
    }
    try output.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
  }

  /// Recursively writes the information in the test tree to the given string.
  private func writeTestTree(_ tree: TestTree, indentation: String, to output: inout String) {
    for (name, child) in tree.children {
      if let testInfo = child.value {
        // This is a test case, so write the appropriate node and all of its issues.
        output += #"""
          \#(indentation)<testcase name="\#(xmlEscaping: name)" status="run" result="completed" \#
          time="\#(testInfo.durationInSeconds)">

          """#
        for issue in testInfo.issues {
          output += #"""
            \#(indentation)  <\#(issue.kind.rawValue) message="\#(xmlEscaping: issue.reason)"/>

            """#
        }
        output += #"""
          \#(indentation)</testcase>

          """#
      } else {
        // There's no test data, so it must be a suite. Write the structure and then traverse the
        // children.
        output += #"""
          \#(indentation)<testsuite name="\#(xmlEscaping: name)" status="run" result="completed">

          """#
        writeTestTree(child, indentation: indentation + "  ", to: &output)
        output += #"""
          \#(indentation)</testsuite>

          """#
      }
    }
  }

  /// Records that a test has started.
  public func recordTestStarted(nameComponents: [String], time: TestInstant) {
    context.withLock { context in
      context.testCount += 1
      context.testData[nameComponents] = .init(startTime: time)
    }
  }

  /// Records that a test has ended.
  public func recordTestEnded(nameComponents: [String], time: TestInstant) {
    context.withLock { context in
      context.testData[nameComponents]?.endTime = time
    }
  }

  /// Records that an issue has occurred during a test.
  public func recordTestIssue(nameComponents: [String], issue: RecordedIssue) {
    context.withLock { context in
      context.testData[nameComponents]?.issues.append(issue)

      switch issue.kind {
      case .failure, .error:
        context.hasFailure = true
      default:
        break
      }
    }
  }
}

/// A tree structure that stores information about test suites, tests, and their results.
private struct TestTree: Sendable {
  /// The test information for this node, if it represents a test case.
  var value: TestInfo? = nil

  /// The child nodes of this node.
  var children: [String: TestTree] = [:]

  /// Gets or sets the test information for a node at the given path in the tree.
  subscript(keyPath: some Collection<String>) -> TestInfo? {
    get {
      if let key = keyPath.first {
        return children[key]?[keyPath.dropFirst()]
      } else {
        return self.value
      }
    }
    set {
      if let key = keyPath.first {
        var child = children[key] ?? TestTree()
        child[keyPath.dropFirst()] = newValue
        children[key] = child
      } else {
        self.value = newValue
      }
    }
  }
}

/// An instant in time, expressed as seconds from an unspecified monotonic basis.
///
/// This deliberately avoids Swift's `Clock`/`InstantProtocol`/`Duration` API, which is only
/// available on iOS 16, macOS 13 and later. `test_observer` is linked into every `swift_test`
/// binary, so it has to compile at whatever deployment target the test target uses -- and
/// `swift_test` places no lower bound on that. Only differences between instants are ever
/// meaningful, so seconds from an arbitrary basis is sufficient.
public struct TestInstant: Sendable, Comparable {
  /// The number of seconds since this instant's (unspecified) basis.
  public var seconds: Double

  public init(seconds: Double) {
    self.seconds = seconds
  }

  /// Returns the current instant on a monotonic clock that does not advance while the machine is
  /// suspended, matching the semantics of the `SuspendingClock` this replaces.
  public static var now: TestInstant {
    return TestInstant(seconds: Double(DispatchTime.now().uptimeNanoseconds) / 1e9)
  }

  /// Returns the number of seconds from this instant to the given instant.
  public func seconds(to other: TestInstant) -> Double {
    return other.seconds - self.seconds
  }

  public static func < (lhs: TestInstant, rhs: TestInstant) -> Bool {
    return lhs.seconds < rhs.seconds
  }
}

/// Information about a test case.
private struct TestInfo: Sendable {
  /// The time that the test started.
  var startTime: TestInstant

  /// The time that the test ended.
  var endTime: TestInstant?

  /// Issues that were recorded during the test.
  var issues: [RecordedIssue]

  /// The duration of the test, in seconds, as a string.
  var durationInSeconds: String {
    guard let endTime = endTime else {
      return ""
    }
    return String(format: "%.3f", startTime.seconds(to: endTime))
  }

  /// Creates a new test that started at the given time.
  init(startTime: TestInstant) {
    self.startTime = startTime
    self.endTime = nil
    self.issues = []
  }
}

// Copyright 2022 The Bazel Authors. All rights reserved.
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
import XCTest

/// An XCTest observer that reports its events to the shared `XUnitTestRecorder`.
public final class BazelXMLTestObserver: NSObject {
  /// The default XCTest observer.
  @MainActor
  public static let `default`: BazelXMLTestObserver = .init()

  private override init() {
    super.init()
  }
}

extension BazelXMLTestObserver: XCTestObservation {
  public func testCaseWillStart(_ testCase: XCTestCase) {
    XUnitTestRecorder.shared.recordTestStarted(
      nameComponents: testCase.xUnitNameComponents,
      time: SuspendingClock.now)
  }

  public func testCaseDidFinish(_ testCase: XCTestCase) {
    XUnitTestRecorder.shared.recordTestEnded(
      nameComponents: testCase.xUnitNameComponents,
      time: SuspendingClock.now)
  }

  // On platforms with the Objective-C runtime, we use the richer `XCTIssue`-based APIs. Anywhere
  // else, we're building with the open-source version of XCTest which has only the older
  // `didFailWithDescription` API.
  #if canImport(ObjectiveC)
    public func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
      let tag: RecordedIssue.Kind
      switch issue.type {
      case .assertionFailure, .performanceRegression, .unmatchedExpectedFailure:
        tag = .failure
      case .system, .thrownError, .uncaughtException:
        tag = .error
      @unknown default:
        tag = .failure
      }

      XUnitTestRecorder.shared.recordTestIssue(
        nameComponents: testCase.xUnitNameComponents,
        issue: .init(kind: tag, reason: issue.compactDescription))
    }
  #else
    public func testCase(
      _ testCase: XCTestCase,
      didFailWithDescription description: String,
      inFile filePath: String?,
      atLine lineNumber: Int
    ) {
      let tag: RecordedIssue.Kind = description.hasPrefix(#"threw error ""#) ? .error : .failure
      XUnitTestRecorder.shared.recordTestIssue(
        nameComponents: testCase.xUnitNameComponents,
        issue: .init(kind: tag, reason: description))
    }
  #endif
}

// Hacks ahead! XCTest does not declare the methods that it uses to notify observers of skipped
// tests as part of the public `XCTestObservation` protocol. Instead, they are only available on
// various framework-internal protocols that XCTest checks for conformance against at runtime.
//
// On Darwin platforms, thanks to the Objective-C runtime, we can declare protocols with the same
// names in our library and implement those methods, and XCTest will call them so that we can log
// the skipped tests in our output. Note that we have to re-specify the protocol name in the `@objc`
// attribute to remove the module name for the runtime.
//
// On non-Darwin platforms, we don't have an escape hatch because XCTest is implemented in pure
// Swift and we can't play the same runtime games, so skipped tests simply get tracked as "passing"
// there.
#if canImport(ObjectiveC)
  /// Declares the observation method that is called by XCTest in Xcode 12.5 when a test case is
  /// skipped.
  @objc(_XCTestObservationInternal)
  protocol _XCTestObservationInternal {
    func testCase(
      _ testCase: XCTestCase,
      wasSkippedWithDescription description: String,
      sourceCodeContext: XCTSourceCodeContext?)
  }

  extension BazelXMLTestObserver: _XCTestObservationInternal {
    public func testCase(
      _ testCase: XCTestCase,
      wasSkippedWithDescription description: String,
      sourceCodeContext: XCTSourceCodeContext?
    ) {
      self.testCase(
        testCase,
        didRecordSkipWithDescription: description,
        sourceCodeContext: sourceCodeContext)
    }
  }

  /// Declares the observation method that is called by XCTest in Xcode 13 and later when a test
  /// case is skipped.
  @objc(_XCTestObservationPrivate)
  protocol _XCTestObservationPrivate {
    func testCase(
      _ testCase: XCTestCase,
      didRecordSkipWithDescription description: String,
      sourceCodeContext: XCTSourceCodeContext?)
  }

  extension BazelXMLTestObserver: _XCTestObservationPrivate {
    public func testCase(
      _ testCase: XCTestCase,
      didRecordSkipWithDescription description: String,
      sourceCodeContext: XCTSourceCodeContext?
    ) {
      XUnitTestRecorder.shared.recordTestIssue(
        nameComponents: testCase.xUnitNameComponents,
        issue: .init(kind: .skipped, reason: description))
    }
  }
#endif

extension XCTestCase {
  /// Canonicalizes the name of the test case to the list of string components expected by
  /// `XUnitTestRecorder`.
  ///
  /// The canonical name components of a test are `["TestClass", "testMethod"]`. XCTests run on
  /// Linux will be named `TestClass.testMethod` and are split on the dot. Tests run under the
  /// Objective-C runtime will have Objective-C-style names (i.e., `-[TestClass testMethod]`), which
  /// are likewise converted to the desired form.
  var xUnitNameComponents: [String] {
    guard name.hasPrefix("-[") && name.hasSuffix("]") else {
      return name.split(separator: ".").map(String.init)
    }

    let trimmedName = name.dropFirst(2).dropLast()
    guard let spaceIndex = trimmedName.lastIndex(of: " ") else {
      return String(trimmedName).split(separator: ".").map(String.init)
    }

    return [
      String(trimmedName[..<spaceIndex]),
      String(trimmedName[trimmedName.index(after: spaceIndex)...]),
    ]
  }
}

// Copyright 2026 The Bazel Authors. All rights reserved.
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

import XCTest

/// Records the `XCTest` methods that actually executed during the test run so a subsequent
/// `swift-testing` `@Test` function can assert that every expected `XCTest` method ran.
@MainActor
public enum RecordedTestRuns {
  public static var executed: Set<String> = []

  public static func record(_ identifier: String) {
    executed.insert(identifier)
  }
}

/// A base `XCTestCase` in a support library to verify that `swift_test` discovers inherited
/// `test*` methods from transitive dependencies while allowing subclasses to override them.
open class BaseTestCase: XCTestCase {
  #if canImport(ObjectiveC)
    override open class var defaultTestSuite: XCTestSuite {
      // On Apple platforms, `XCTestSuite.default` discovers all `XCTestCase` subclasses via the
      // Objective-C runtime without scoping to `SWIFT_TEST_DISCOVERY_MODULES`. Return an empty
      // suite for `BaseTestCase` itself so only its concrete subclasses run.
      if self == BaseTestCase.self {
        return XCTestSuite(name: String(describing: self))
      }
      return super.defaultTestSuite
    }
  #endif

  @MainActor
  open func testInheritedFromBase() {
    RecordedTestRuns.record("\(type(of: self)).testInheritedFromBase")
  }

  @MainActor
  open func testOverriddenBySubclass() {
    RecordedTestRuns.record("\(type(of: self)).testOverriddenBySubclass:Base")
  }
}

#if !canImport(ObjectiveC)
  /// A standalone `XCTestCase` in a non-direct or non-scanned dependency module. On platforms that
  /// scope discovery to `SWIFT_TEST_DISCOVERY_MODULES`, this suite must never be discovered or run.
  final class UnscannedModuleStandaloneTestCase: XCTestCase {
    func testShouldNeverBeDiscoveredAsStandaloneSuite() {
      XCTFail("Standalone XCTestCase in an unscanned dependency module should not be discovered")
    }
  }
#endif

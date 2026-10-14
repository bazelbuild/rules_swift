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

import BaseTestSupport
import Testing
import XCTest

final class DirectDepTestSuite: BaseTestCase {
  @MainActor
  func testSync() {
    RecordedTestRuns.record("DirectDepTestSuite.testSync")
  }

  @MainActor
  func testSyncThrows() throws {
    RecordedTestRuns.record("DirectDepTestSuite.testSyncThrows")
  }

  @MainActor
  func testAsync() async {
    RecordedTestRuns.record("DirectDepTestSuite.testAsync")
  }

  @MainActor
  func testAsyncThrows() async throws {
    RecordedTestRuns.record("DirectDepTestSuite.testAsyncThrows")
  }

  @MainActor
  override func testOverriddenBySubclass() {
    RecordedTestRuns.record("DirectDepTestSuite.testOverriddenBySubclass:Derived")
  }

  func testWithParam(_ value: Int) {
    XCTFail("Method with parameter should not be discovered: \(value)")
  }

  func testWithReturnValue() -> Int {
    XCTFail("Method with return value should not be discovered")
    return 0
  }

  private func testPrivateMethod() {
    XCTFail("Private method should not be discovered")
  }

  func helperNotATest() {
    XCTFail("Non-test method should not be discovered")
  }
}

extension DirectDepTestSuite {
  @MainActor
  func testInExtension() {
    RecordedTestRuns.record("DirectDepTestSuite.testInExtension")
  }

  @MainActor
  func testAsyncInExtension() async {
    RecordedTestRuns.record("DirectDepTestSuite.testAsyncInExtension")
  }
}

@MainActor
@Test func `all expected XCTest methods in TestOnlyLib actually ran`() {
  #expect(
    RecordedTestRuns.executed == [
      "DirectDepTestSuite.testInheritedFromBase",
      "DirectDepTestSuite.testOverriddenBySubclass:Derived",
      "DirectDepTestSuite.testSync",
      "DirectDepTestSuite.testSyncThrows",
      "DirectDepTestSuite.testAsync",
      "DirectDepTestSuite.testAsyncThrows",
      "DirectDepTestSuite.testInExtension",
      "DirectDepTestSuite.testAsyncInExtension",
    ]
  )
}

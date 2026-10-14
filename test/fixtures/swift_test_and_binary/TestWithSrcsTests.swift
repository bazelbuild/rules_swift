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

final class OwnerSrcsTestSuite: BaseTestCase {
  @MainActor
  func testSync() {
    RecordedTestRuns.record("OwnerSrcsTestSuite.testSync")
  }

  @MainActor
  func testSyncThrows() throws {
    RecordedTestRuns.record("OwnerSrcsTestSuite.testSyncThrows")
  }

  @MainActor
  func testAsync() async {
    RecordedTestRuns.record("OwnerSrcsTestSuite.testAsync")
  }

  @MainActor
  func testAsyncThrows() async throws {
    RecordedTestRuns.record("OwnerSrcsTestSuite.testAsyncThrows")
  }

  @MainActor
  override func testOverriddenBySubclass() {
    RecordedTestRuns.record("OwnerSrcsTestSuite.testOverriddenBySubclass:Derived")
  }
}

extension OwnerSrcsTestSuite {
  @MainActor
  func testInExtension() {
    RecordedTestRuns.record("OwnerSrcsTestSuite.testInExtension")
  }
}

@MainActor
@Test func `all expected XCTest methods in TestWithSrcs actually ran`() {
  #expect(
    RecordedTestRuns.executed == [
      "OwnerSrcsTestSuite.testInheritedFromBase",
      "OwnerSrcsTestSuite.testOverriddenBySubclass:Derived",
      "OwnerSrcsTestSuite.testSync",
      "OwnerSrcsTestSuite.testSyncThrows",
      "OwnerSrcsTestSuite.testAsync",
      "OwnerSrcsTestSuite.testAsyncThrows",
      "OwnerSrcsTestSuite.testInExtension",
    ]
  )
}

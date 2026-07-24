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

#if os(Linux)
  import Foundation
  import XCTest

  public typealias XCTestRunner = LinuxXCTestRunner

  /// A test runner for tests that use the XCTest framework on Linux.
  ///
  /// This test runner uses test case entries that were constructed by scanning the symbol graph
  /// output of the compiler.
  @MainActor
  public enum LinuxXCTestRunner {
    /// A wrapper around a single test from an `XCTestCaseEntry` used by the test collector.
    private struct Test: Testable {
      /// The type of the `XCTestCase` that contains the test.
      var testCaseClass: XCTestCase.Type

      /// The name of the test and the closure that runs it.
      var xcTest: (String, XCTestCaseClosure)

      var testIdentifier: String {
        "\(String(describing: testCaseClass))/\(xcTest.0)"
      }
    }

    /// A thin wrapper around a `XCTestCase` metatype that allows it to be used as a key in a
    /// dictionary.
    private struct TestCaseType: Equatable, Hashable {
      var testCaseClass: XCTestCase.Type

      init(_ testCaseClass: XCTestCase.Type) {
        self.testCaseClass = testCaseClass
      }

      static func == (lhs: TestCaseType, rhs: TestCaseType) -> Bool {
        return lhs.testCaseClass == rhs.testCaseClass
      }

      func hash(into hasher: inout Hasher) {
        return hasher.combine(ObjectIdentifier(testCaseClass))
      }
    }

    public static func run(_ testCaseEntries: [XCTestCaseEntry]) throws {
      XCTestObservationCenter.shared.addTestObserver(BazelXMLTestObserver.default)
      // The preferred overload normally chosen by the compiler is one that calls `exit`, which we
      // don't want because we have post-work to do, so force the one that returns an exit code
      // instead (which we ignore).
      let _: CInt = XCTMain(try shard(testCaseEntries))
    }

    /// Returns a filtered and sharded copy of the given list of test case entries.
    private static func shard(_ testCaseEntries: [XCTestCaseEntry]) throws -> [XCTestCaseEntry] {
      var collector = try ShardingFilteringTestCollector<Test>()
      guard collector.willShardOrFilter else {
        return testCaseEntries
      }

      for testCaseEntry in testCaseEntries {
        for test in testCaseEntry.allTests {
          collector.addTest(Test(testCaseClass: testCaseEntry.testCaseClass, xcTest: test))
        }
      }

      // Group the sharded tests back into buckets based on their test case class.
      var shardedEntryMap: [TestCaseType: [(String, XCTestCaseClosure)]] = [:]
      for shardedTest in collector.testsInCurrentShard {
        shardedEntryMap[TestCaseType(shardedTest.testCaseClass), default: []]
          .append(shardedTest.xcTest)
      }
      return
        shardedEntryMap
        .map { ($0.testCaseClass, $1) }
        .sorted { String(describing: $0.0) < String(describing: $1.0) }
    }
  }
#endif

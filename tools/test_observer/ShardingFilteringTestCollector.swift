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

/// Types representing tests that can be processed by the test collector should implement this
/// protocol to provide the test identifier that will be checked against the `--test_filter`
/// regular expression.
protocol Testable {
  /// The unique identifier for this test, which will be checked against the `--test_filter`
  /// regular expression.
  var testIdentifier: String { get }
}

/// A test collector that filters out tests that should not be run in the current shard and also
/// filters out tests that do not match the `--test_filter` regular expression.
struct ShardingFilteringTestCollector<Test: Testable> {
  struct Error: Swift.Error, CustomStringConvertible {
    var message: String
    var description: String { message }
  }

  private(set) var testsInCurrentShard: [Test]

  private var shardCount: Int
  private var shardIndex: Int
  private var seenTestCount: Int
  private var filter: Regex<AnyRegexOutput>?

  /// Indicates whether the next test added to the collector should be included in the current
  /// shard.
  private var isCurrentShard: Bool {
    return shardCount == 0 || seenTestCount % shardCount == shardIndex
  }

  /// Indicates whether sharding or filtering was requested.
  ///
  /// This property can be used as a fast-path to avoid walking the test hierarchy if no
  /// sharding or filtering is requested.
  var willShardOrFilter: Bool {
    shardCount != 0 || filter != nil
  }

  /// Creates a new test collector.
  ///
  /// - Throws: If the environment variables indicating sharding and/or filtering are invalid.
  init() throws {
    // Bazel requires us to write out an empty file at this path to tell it that we support
    // sharding.
    let environment = ProcessInfo.processInfo.environment
    if let statusPath = environment["TEST_SHARD_STATUS_FILE"] {
      guard FileManager.default.createFile(atPath: statusPath, contents: nil, attributes: nil)
      else {
        throw Error(message: "Could not create TEST_SHARD_STATUS_FILE (\(statusPath))")
      }
    }

    self.shardCount = environment["TEST_TOTAL_SHARDS"].flatMap { Int($0, radix: 10) } ?? 0
    self.shardIndex = environment["TEST_SHARD_INDEX"].flatMap { Int($0, radix: 10) } ?? 0
    self.seenTestCount = 0
    self.testsInCurrentShard = []

    guard (shardCount == 0 && shardIndex == 0) || (shardCount > 0 && shardIndex < shardCount)
    else {
      throw Error(
        message: "Invalid shard count (\(shardCount)) and shard index (\(shardIndex))")
    }
    if let filterString = environment["TESTBRIDGE_TEST_ONLY"] {
      guard let maybeFilter = try? Regex(filterString) else {
        throw Error(
          message: """
            Could not parse '--test_filter' string as a regular expression: \(filterString)
            """)
      }
      self.filter = maybeFilter
    } else {
      self.filter = nil
    }
  }

  /// Adds a test to the collector.
  ///
  /// If the test does not match the `--test_filter` regular expression, it will be ignored. If it
  /// belongs in the current shard, it will be added to the list of tests to run in that shard.
  mutating func addTest(_ test: Test) {
    guard isIncludedByFilter(test.testIdentifier) else {
      // Tests that are filtered out do not advance the shard.
      return
    }
    if isCurrentShard {
      self.testsInCurrentShard.append(test)
    }
    self.seenTestCount += 1
  }

  /// Returns `true` if the given test identifier matches the `--test_filter` regular expression.
  private func isIncludedByFilter(_ testIdentifier: String) -> Bool {
    guard let filter = self.filter else { return true }
    do {
      return try filter.firstMatch(in: testIdentifier) != nil
    } catch {
      return false
    }
  }
}

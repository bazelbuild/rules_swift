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

let availabilityAttribute = """
  @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow \
  inclusion of deprecated tests (which test deprecated functionality) without warnings.")
  """

/// Creates a text file with the given contents at a file URL.
func createTextFile(at url: URL, contents: String) {
  FileManager.default.createFile(atPath: url.path, contents: contents.data(using: .utf8)!)
}

/// The parts of the `ShardingAwareTestCollector` type that are common to both the Objective-C and
/// symbol-graph-based implementations. Those generators then should add extensions to provide
/// runner-specific logic.
func createShardingFilteringTestCollector(extraProperties: String = "") -> String {
  return """
    struct ShardingFilteringTestCollector {
      struct Error: Swift.Error, CustomStringConvertible {
        var message: String
        var description: String { message }
      }

      private var shardCount: Int
      private var shardIndex: Int
      private var seenTestCount: Int
      private var filter: Regex<AnyRegexOutput>?
      \(extraProperties)

      init() throws {
        // Bazel requires us to write out an empty file at this path to tell it that we support
        // sharding.
        if let statusPath = ProcessInfo.processInfo.environment["TEST_SHARD_STATUS_FILE"] {
          guard FileManager.default.createFile(atPath: statusPath, contents: nil, attributes: nil)
          else {
            throw Error(message: "Could not create TEST_SHARD_STATUS_FILE (\\(statusPath))")
          }
        }

        self.shardCount =
          ProcessInfo.processInfo.environment["TEST_TOTAL_SHARDS"].flatMap { Int($0, radix: 10) } ?? 0
        self.shardIndex =
          ProcessInfo.processInfo.environment["TEST_SHARD_INDEX"].flatMap { Int($0, radix: 10) } ?? 0
        self.seenTestCount = 0

        guard (shardCount == 0 && shardIndex == 0) || (shardCount > 0 && shardIndex < shardCount)
        else {
          throw Error(
            message: "Invalid shard count (\\(shardCount)) and shard index (\\(shardIndex))")
        }
        if let filterString = ProcessInfo.processInfo.environment["TESTBRIDGE_TEST_ONLY"] {
          guard let maybeFilter = try? Regex(filterString) else {
            throw Error(message: "Could not parse '--test_filter' string as a regular expression")
          }
          filter = maybeFilter
        } else {
          filter = nil
        }
      }

      private func isIncludedByFilter(_ testName: String) -> Bool {
        guard let filter = self.filter else { return true }
        do {
          return try filter.wholeMatch(in: testName) != nil
        } catch {
          return false
        }
      }
    }

    """
}
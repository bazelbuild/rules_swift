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

/// Prints a test runner as Swift source code to be compiled in order to run the tests.
///
/// To support Bazel's test sharding protocol and better test filtering, this runner is not based
/// on an XCTest bundle but instead is an executable that queries the XCTest framework directly for
/// the tests to run.
struct ObjcTestPrinter {
  /// Prints the main test runner to a Swift source file.
  func printTestRunner(toFileAt url: URL) {
    var contents = """
      import BazelTestObservation
      import Foundation
      import XCTest

      @main
      \(availabilityAttribute)
      struct Runner {
        static func main() {
          loadXCTest()
          if let xmlObserver = BazelXMLTestObserver.default {
            XCTestObservationCenter.shared.addTestObserver(xmlObserver)
          }
          do {
            var testCollector = try ShardingFilteringTestCollector()
            let shardedSuite = testCollector.shard(XCTestSuite.default)
            shardedSuite.run()
            if let testRun = shardedSuite.testRun {
              if testRun.testCaseCount == 0 {
                print("ERROR: No tests were executed")
                exit(1)
              }
              exit(testRun.totalFailureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
            }
          } catch {
            print("ERROR: \\(error); exiting.")
            exit(1)
          }
        }
      }

      private func loadXCTest() {
        // We weakly linked to XCTest.framework and the Swift support dylib because the machine
        // that links the test binary might not be the same that runs it, and they might have Xcode
        // installed at different paths. Find the path that Bazel says they're installed at on
        // *this* machine and load them.
        guard let sdkRoot = ProcessInfo.processInfo.environment["SDKROOT"] else {
          print("ERROR: Bazel must set the SDKROOT in order to find XCTest")
          exit(1)
        }
        let sdkRootURL = URL(fileURLWithPath: sdkRoot)
        let platformDeveloperPath = sdkRootURL  // .../Developer/SDKs/MacOSX.sdk
          .deletingLastPathComponent()  // .../Developer/SDKs
          .deletingLastPathComponent()  // .../Developer
        let xcTestPath = platformDeveloperPath
          .appendingPathComponent("Library/Frameworks/XCTest.framework/XCTest")
          .path
        guard dlopen(xcTestPath, RTLD_NOW) != nil else {
          print("ERROR: dlopen(\\"\\(xcTestPath)\\") failed")
          exit(1)
        }
        let xcTestSwiftSupportPath = platformDeveloperPath
          .appendingPathComponent("usr/lib/libXCTestSwiftSupport.dylib")
          .path
        guard dlopen(xcTestSwiftSupportPath, RTLD_NOW) != nil else {
          print("ERROR: dlopen(\\"\\(xcTestSwiftSupportPath)\\") failed")
          exit(1)
        }
      }

      """
    contents += createShardingFilteringTestCollector()
    contents += """
      extension ShardingFilteringTestCollector {
        mutating func shard(_ suite: XCTestSuite) -> XCTestSuite {
          guard shardCount != 0 || filter != nil else {
            // If we're not sharding or filtering, just return the original suite.
            return suite
          }

          // Create an empty suite with the same name. We'll recurse through the original suite,
          // retaining any nested suite structures but only adding 1 of every `shard_count` tests
          // we encounter.
          let shardedSuite = XCTestSuite(name: suite.name)
          for test in suite.tests {
            switch test {
            case let childSuite as XCTestSuite:
              shardedSuite.addTest(shard(childSuite))
            default:
              guard isIncludedByFilter(nameForFiltering(of: test)) else {
                break
              }
              if isIncludedInShard() {
                shardedSuite.addTest(test)
              }
              seenTestCount += 1
            }
          }
          return shardedSuite
        }

        private func nameForFiltering(of test: XCTest) -> String {
          let name = test.name
          guard name.hasPrefix("-[") && name.hasSuffix("]") else {
            return name
          }

          let trimmedName = name.dropFirst(2).dropLast()
          guard let spaceIndex = trimmedName.lastIndex(of: " ") else {
            return String(trimmedName)
          }

          return "\\(trimmedName[..<spaceIndex])/\\(trimmedName[trimmedName.index(after: spaceIndex)...])"
        }
      }

      """

    createTextFile(at: url, contents: contents)
  }
}

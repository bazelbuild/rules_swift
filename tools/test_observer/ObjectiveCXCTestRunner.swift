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

#if canImport(ObjectiveC)
  import Foundation
  import XCTest

  @available(*, deprecated, message: """
    Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which \
    test deprecated functionality) without warnings.
    """)
  public typealias XCTestRunner = ObjectiveCXCTestRunner

  @available(*, deprecated, message: """
    Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which \
    test deprecated functionality) without warnings.
    """)
  @MainActor
  public enum ObjectiveCXCTestRunner {
    struct Error: Swift.Error, CustomStringConvertible {
      let description: String
    }

    /// A wrapper around an `XCTestCase` used by the test collector.
    struct Test: Testable {
      /// The underlying `XCTestCase` that this wrapper represents.
      private(set) var xcTest: XCTest

      var testIdentifier: String {
        let name = xcTest.name
        guard name.hasPrefix("-[") && name.hasSuffix("]") else {
          // If it's not an Objective-C method name, just return it verbatim.
          return name
        }
        // Split the class name from the method name and then re-join them using the slash form that
        // the test filter expects.
        let trimmedName = name.dropFirst(2).dropLast()
        guard let spaceIndex = trimmedName.lastIndex(of: " ") else {
          return String(trimmedName)
        }
        return "\(trimmedName[..<spaceIndex])/\(trimmedName[trimmedName.index(after: spaceIndex)...])"
      }
    }

    public static func run(_ unused: ()) throws {
      try loadXCTest()
      XCTestObservationCenter.shared.addTestObserver(BazelXMLTestObserver.default)
      try shard(XCTestSuite.default).run()
    }

    /// Loads the XCTest framework and Swift support dylib.
    ///
    /// We weakly link against XCTest.framework and the Swift support dylib because the machine that
    /// links the test binary might not be the same that runs it, and they might have Xcode
    /// installed at different paths. To handle this, we find the path that Bazel says they're
    /// installed at on the machine where the test is running and load them dynamically.
    private static func loadXCTest() throws {
      guard let sdkRoot = ProcessInfo.processInfo.environment["SDKROOT"] else {
        throw Error(description: "ERROR: Bazel must set the SDKROOT in order to find XCTest")
      }
      let sdkRootURL = URL(fileURLWithPath: sdkRoot)
      let platformDeveloperPath = sdkRootURL  // .../Developer/SDKs/MacOSX.sdk
        .deletingLastPathComponent()  // .../Developer/SDKs
        .deletingLastPathComponent()  // .../Developer
      let xcTestPath = platformDeveloperPath
        .appendingPathComponent("Library/Frameworks/XCTest.framework/XCTest")
        .path
      guard dlopen(xcTestPath, RTLD_NOW) != nil else {
        throw Error(description: #"ERROR: dlopen("\#(xcTestPath)") failed"#)
      }
      let xcTestSwiftSupportPath = platformDeveloperPath
        .appendingPathComponent("usr/lib/libXCTestSwiftSupport.dylib")
        .path
      guard dlopen(xcTestSwiftSupportPath, RTLD_NOW) != nil else {
        throw Error(description: #"ERROR: dlopen("\#(xcTestSwiftSupportPath)") failed"#)
      }
    }

    /// Returns a new `XCTestSuite` that contains a filtered and sharded copy of the tests in the
    /// given suite.
    private static func shard(_ suite: XCTestSuite) throws -> XCTestSuite {
      var testCollector = try ShardingFilteringTestCollector<Test>()
      guard testCollector.willShardOrFilter else {
        // If we're not sharding or filtering, just return the original suite.
        return suite
      }

      let shardedSuite = XCTestSuite(name: suite.name)
      shard(suite, into: &testCollector)
      for test in testCollector.testsInCurrentShard {
        shardedSuite.addTest(test.xcTest)
      }
      return shardedSuite
    }

    private static func shard(
      _ suite: XCTestSuite,
      into collector: inout ShardingFilteringTestCollector<Test>
    ) {
      // Create an empty suite with the same name. We'll recurse through the original suite,
      // retaining any nested suite structures but only adding 1 of every `shard_count` tests
      // we encounter.
      for test in suite.tests {
        switch test {
        case let childSuite as XCTestSuite:
          shard(childSuite, into: &collector)
        default:
          collector.addTest(Test(xcTest: test))
        }
      }
    }
  }
#endif

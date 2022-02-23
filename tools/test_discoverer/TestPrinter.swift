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

private let availabilityAttribute = """
  @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow \
  inclusion of deprecated tests (which test deprecated functionality) without warnings.")
  """

/// Creates a text file with the given contents at a file URL.
private func createTextFile(at url: URL, contents: String) {
  FileManager.default.createFile(atPath: url.path, contents: contents.data(using: .utf8)!)
}

/// Returns a Swift expression used to populate the function references in the `XCTestCaseEntry`
/// array for the given test method.
///
/// The returned string considers whether the test is declared `async`, wrapping it with a helper
/// function if necessary.
private func generatedTestEntry(for method: DiscoveredTests.Method) -> String {
  if method.isAsync {
    return "asyncTest(\(method.name))"
  } else {
    return method.name
  }
}

/// Prints discovered test entries and a test runner as Swift source code to be compiled in order to
/// run the tests.
struct TestPrinter {
  /// The discovered tests whose entries and runner should be printed as Swift source code.
  let discoveredTests: DiscoveredTests

  init(discoveredTests: DiscoveredTests) {
    self.discoveredTests = discoveredTests
  }

  /// Writes the accessor for the test entries discovered in the given module to a Swift source
  /// file.
  func printTestEntries(forModule moduleName: String, toFileAt url: URL) {
    guard let discoveredModule = discoveredTests.modules[moduleName] else {
      // No tests were discovered in a module passed to the tool, but Bazel still declared the file
      // and expects us to generate something, so print an "empty" file for it to compile.
      createTextFile(
        at: url,
        contents: """
          // No tests were discovered in module \(moduleName).

          """)
      return
    }

    var contents = """
      import XCTest
      @testable import \(moduleName)

      """

    let sortedClassNames = discoveredModule.classes.keys.sorted()
    for className in sortedClassNames {
      let testClass = discoveredModule.classes[className]!

      contents += """

        fileprivate extension \(className) {
          \(availabilityAttribute)
          static let __allTests = [

        """

      for testMethod in testClass.methods.sorted(by: { $0.name < $1.name }) {
        contents += """
              ("\(testMethod.name)", \(generatedTestEntry(for: testMethod))),

          """
      }

      contents += """
          ]
        }

        """
    }

    contents += """

      \(availabilityAttribute)
      func __\(moduleName)__allTests() -> [XCTestCaseEntry] {
        return [

      """

    for className in sortedClassNames {
      contents += """
            testCase(\(className).__allTests),

        """
    }

    contents += """
        ]
      }

      """

    createTextFile(at: url, contents: contents)
  }

  /// Prints the main test runner to a Swift source file.
  func printTestRunner(toFileAt url: URL) {
    var contents = """
      import XCTest

      @main
      \(availabilityAttribute)
      struct Runner {
        static func main() {
          var tests = [XCTestCaseEntry]()

      """

    for moduleName in discoveredTests.modules.keys.sorted() {
      contents += """
            tests += __\(moduleName)__allTests()

        """
    }

    contents += """
          XCTMain(tests)
        }
      }

      """

    createTextFile(at: url, contents: contents)
  }
}

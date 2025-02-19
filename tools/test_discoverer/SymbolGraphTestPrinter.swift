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

/// Returns a Swift expression used to populate the function references in the `XCTestCaseEntry`
/// array for the given test method.
///
/// The returned string considers whether the test is declared `async`, wrapping it with a helper
/// function if necessary.
private func generatedTestEntry(for method: DiscoveredTests.Method) -> String {
  if method.isAsync {
    return "asyncTest({ type in type.\(method.name) })"
  } else {
    return method.name
  }
}

/// Returns the Swift identifier that represents the generated array of test entries for the given
/// test class.
private func allTestsIdentifier(for testClass: DiscoveredTests.Class) -> String {
  return "__allTests__\(testClass.name)"
}

/// Returns the Swift identifier that represents the generated function that returns the combined
/// test entries for all the test classes in the given module.
private func allTestsIdentifier(for module: DiscoveredTests.Module) -> String {
  return "\(module.name)__allTests"
}

/// Prints discovered test entries and a test runner as Swift source code to be compiled in order to
/// run the tests.
struct SymbolGraphTestPrinter {
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
          static func \(allTestsIdentifier(for: testClass))()
            -> [(String, (\(className)) -> () throws -> Void)]
          {
            return [

        """

      for testMethod in testClass.methods.sorted(by: { $0.name < $1.name }) {
        contents += """
                ("\(testMethod.name)", \(generatedTestEntry(for: testMethod))),

          """
      }

      contents += """
            ]
          }
        }

        """
    }

    contents += """

      \(availabilityAttribute)
      @MainActor
      func \(allTestsIdentifier(for: discoveredModule))() -> [XCTestCaseEntry] {
        return [

      """

    for className in sortedClassNames {
      let testClass = discoveredModule.classes[className]!
      contents += """
            testCase(\(className).\(allTestsIdentifier(for: testClass))()),

        """
    }

    contents += """
        ]
      }

      """

    createTextFile(at: url, contents: contents)
  }

  /// Returns the Swift source code for the test runner.
  func testRunnerSource() -> String {
    guard !discoveredTests.modules.isEmpty else {
      // If no tests were discovered, the user likely wrote non-XCTest-style tests that pass or fail
      // based on the exit code of the process. Generate an empty source file here, which will be
      // harmlessly compiled as an empty module, and the user's `main` from their own sources will
      // be used instead.
      return """
        @MainActor
        private func __allDiscoveredXCTests() -> [XCTestCaseEntry] { [] }

        """
    }

    var contents = """
      \(availabilityAttribute)
      @MainActor
      private func __allDiscoveredXCTests() -> [XCTestCaseEntry] {
        var allTests: [XCTestCaseEntry] = []

      """

    for moduleName in discoveredTests.modules.keys.sorted() {
      let module = discoveredTests.modules[moduleName]!
      contents += """
          allTests.append(contentsOf: \(allTestsIdentifier(for: module))())

        """
    }

    contents += """
        return allTests
      }

      """

    return contents
  }
}

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

import Foundation
import SymbolKit
import Testing
import tools_test_discoverer_test_discoverer

struct TestDiscovererTests {
  @Test func `SymbolCollector discovers direct and inherited XCTests`() throws {
    let discovered = try loadFixtureDiscoveredTests()
    #expect(discovered.modules.count == 1)

    let module = try #require(discovered.modules.values.first)
    #expect(Set(module.classes.keys) == ["BaseTestSuite", "DerivedTestSuite"])

    let baseClass = try #require(module.classes["BaseTestSuite"])
    let baseMethods = baseClass.methods.sorted { $0.name < $1.name }
    #expect(baseMethods.count == 2)
    #expect(baseMethods[0].name == "testAsync")
    #expect(baseMethods[0].isAsync)
    #expect(baseMethods[1].name == "testSync")
    #expect(!baseMethods[1].isAsync)

    let derivedClass = try #require(module.classes["DerivedTestSuite"])
    #expect(derivedClass.methods.count == 1)
    #expect(derivedClass.methods[0].name == "testDerived")
    #expect(!derivedClass.methods[0].isAsync)
  }

  @Test func `SymbolGraphTestPrinter formats entries and main source`() throws {
    let discovered = try loadFixtureDiscoveredTests()
    let module = try #require(discovered.modules.values.first)
    let printer = SymbolGraphTestPrinter(discoveredTests: discovered)

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let emptyFileURL = tempDir.appendingPathComponent("EmptyModule.swift")
    printer.printTestEntries(forModule: "EmptyModule", toFileAt: emptyFileURL)
    let emptyContents = try String(contentsOf: emptyFileURL, encoding: .utf8)
    #expect(emptyContents == "// No tests were discovered in module EmptyModule.\n")

    let moduleFileURL = tempDir.appendingPathComponent("FixtureModule.swift")
    printer.printTestEntries(forModule: module.name, toFileAt: moduleFileURL)
    let moduleContents = try String(contentsOf: moduleFileURL, encoding: .utf8)
    #expect(moduleContents.contains("@testable import \(module.name)"))
    #expect(moduleContents.contains("static func __allTests__BaseTestSuite()"))
    #expect(moduleContents.contains("static func __allTests__DerivedTestSuite()"))
    #expect(moduleContents.contains("(\"testSync\", testSync),"))
    #expect(moduleContents.contains("(\"testAsync\", asyncTest({ type in type.testAsync })),"))
    #expect(moduleContents.contains("(\"testDerived\", testDerived),"))
    #expect(moduleContents.contains("func \(module.name)__allTests() -> [XCTestCaseEntry]"))

    let runnerSource = printer.testRunnerSource()
    #expect(runnerSource.contains("@_silgen_name(\"bazel_rules_swift_allDiscoveredXCTests\")"))
    #expect(runnerSource.contains("allTests.append(contentsOf: \(module.name)__allTests())"))
  }
}

private func loadFixtureDiscoveredTests() throws -> DiscoveredTests {
  let env = ProcessInfo.processInfo.environment
  let testSrcDir = try #require(env["TEST_SRCDIR"])
  let rootURL = URL(fileURLWithPath: testSrcDir)
  let enumerator = try #require(
    FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil)
  )
  var foundDirURL: URL?
  for case let url as URL in enumerator {
    if url.lastPathComponent == "fixture_symbol_graphs.symbolgraphs" {
      foundDirURL = url
      break
    }
  }
  let symbolGraphDirURL = try #require(foundDirURL)

  let collector = SymbolCollector()
  let urls = try FileManager.default.contentsOfDirectory(
    at: symbolGraphDirURL,
    includingPropertiesForKeys: nil
  ).sorted { $0.path < $1.path }
  #expect(!urls.isEmpty)

  let decoder = JSONDecoder()
  for url in urls {
    let data = try Data(contentsOf: url)
    let symbolGraph = try decoder.decode(SymbolGraph.self, from: data)
    collector.consume(symbolGraph)
  }

  return collector.discoveredTests()
}

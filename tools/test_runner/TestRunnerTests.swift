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
import Testing
import tools_test_runner_test_runner

private struct DummyTestItem: Testable, Equatable {
  var testIdentifier: String
}

struct TestRunnerTests {
  @Test func `string interpolation XML escaping`() {
    let plain = "normal_identifier_123"
    #expect("\(xmlEscaping: plain)" == "normal_identifier_123")

    let special = #"a < b && c > d || "quoted" == 'single'"#
    #expect(
      "<msg attr=\"\(xmlEscaping: special)\"/>"
        == "<msg attr=\"a &lt; b &amp;&amp; c &gt; d || &quot;quoted&quot; == &apos;single&apos;\"/>"
    )

    let empty = ""
    #expect("\(xmlEscaping: empty)" == "")
  }

  @Test func `JSON encoding and decoding round-trip`() throws {
    let original: JSON = [
      "nullVal": nil,
      "boolTrue": true,
      "boolFalse": false,
      "intVal": 42,
      "minIntVal": .number(Int.min),
      "floatVal": 348956.52160425,
      "stringVal": "hello \"swift\"",
      "arrayVal": [1, "two", false, nil],
    ]

    let data = try original.encodedData
    let decoded = try JSON(byDecoding: data)

    guard case .object(let dict) = decoded else {
      Issue.record("Expected top-level JSON object")
      return
    }
    if case .null = dict["nullVal"] {} else { Issue.record("Expected nullVal to be .null") }
    if case .bool(true) = dict["boolTrue"] {} else { Issue.record("Expected boolTrue == true") }
    if case .bool(false) = dict["boolFalse"] {} else { Issue.record("Expected boolFalse == false") }
    if case .number(let n) = dict["intVal"] {
      #expect(n.intValue == 42)
    } else {
      Issue.record("Expected intVal number")
    }
    if case .number(let minN) = dict["minIntVal"] {
      #expect(minN.intValue == Int.min)
    } else {
      Issue.record("Expected minIntVal number")
    }
    if case .number(let d) = dict["floatVal"] {
      #expect(abs(d.doubleValue - 348956.52160425) < 1e-6)
    } else {
      Issue.record("Expected floatVal number")
    }
    if case .string(let s) = dict["stringVal"] {
      #expect(s == "hello \"swift\"")
    } else {
      Issue.record("Expected stringVal")
    }
    if case .array(let arr) = dict["arrayVal"] {
      #expect(arr.count == 4)
    } else {
      Issue.record("Expected arrayVal")
    }
  }

  @Test func `Locked mutates value safely`() {
    let locked = Locked([1, 2])
    #expect(locked.value == [1, 2])

    let count = locked.withLock { array -> Int in
      array.append(3)
      return array.count
    }
    #expect(count == 3)
    #expect(locked.value == [1, 2, 3])
  }

  @Test func `ShardingFilteringTestCollector default, sharded, and filtered behavior`() throws {
    let items = [
      DummyTestItem(testIdentifier: "SuiteA/test1"),
      DummyTestItem(testIdentifier: "SuiteA/test2"),
      DummyTestItem(testIdentifier: "SuiteB/test1"),
      DummyTestItem(testIdentifier: "SuiteA/test3"),
    ]

    var defaultCollector = try ShardingFilteringTestCollector<DummyTestItem>(environment: [:])
    #expect(!defaultCollector.willShardOrFilter)
    for item in items {
      defaultCollector.addTest(item)
    }
    #expect(defaultCollector.testsInCurrentShard == items)

    let statusFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString
    )
    defer { try? FileManager.default.removeItem(at: statusFileURL) }

    var shardedCollector = try ShardingFilteringTestCollector<DummyTestItem>(environment: [
      "TEST_TOTAL_SHARDS": "2",
      "TEST_SHARD_INDEX": "1",
      "TEST_SHARD_STATUS_FILE": statusFileURL.path,
      "TESTBRIDGE_TEST_ONLY": "^SuiteA/",
    ])
    #expect(shardedCollector.willShardOrFilter)
    #expect(FileManager.default.fileExists(atPath: statusFileURL.path))
    for item in items {
      shardedCollector.addTest(item)
    }
    // Matching items are SuiteA/test1 (idx 0 -> shard 0), SuiteA/test2 (idx 1 -> shard 1),
    // SuiteA/test3 (idx 2 -> shard 0). SuiteB/test1 is filtered out without advancing the shard!
    #expect(shardedCollector.testsInCurrentShard == [DummyTestItem(testIdentifier: "SuiteA/test2")])
  }

  @Test func `ShardingFilteringTestCollector rejects invalid environment variables`() {
    #expect(throws: (any Error).self) {
      try ShardingFilteringTestCollector<DummyTestItem>(environment: [
        "TEST_TOTAL_SHARDS": "2",
        "TEST_SHARD_INDEX": "2",
      ])
    }

    #expect(throws: (any Error).self) {
      try ShardingFilteringTestCollector<DummyTestItem>(environment: [
        "TESTBRIDGE_TEST_ONLY": "[unclosed_regex"
      ])
    }
  }

  @Test func `XUnitTestRecorder tracks issues and writes XML`() throws {
    let recorder = XUnitTestRecorder()
    #expect(!recorder.didTestsRun)
    #expect(!recorder.hasFailure)

    let clock = ContinuousClock()
    let start = clock.now
    let end = start.advanced(by: .milliseconds(250))

    recorder.recordTestStarted(nameComponents: ["MySuite<1>", "testPass"], time: start)
    recorder.recordTestIssue(
      nameComponents: ["MySuite<1>", "testPass"],
      issue: RecordedIssue(kind: .skipped, reason: "skipped \"reason\"")
    )
    recorder.recordTestEnded(nameComponents: ["MySuite<1>", "testPass"], time: end)
    #expect(recorder.didTestsRun)
    #expect(!recorder.hasFailure)

    recorder.recordTestStarted(nameComponents: ["MySuite<1>", "testFail&Error"], time: start)
    recorder.recordTestIssue(
      nameComponents: ["MySuite<1>", "testFail&Error"],
      issue: RecordedIssue(kind: .failure, reason: "expected 1 < 2 & 'ok'")
    )
    recorder.recordTestEnded(nameComponents: ["MySuite<1>", "testFail&Error"], time: end)
    #expect(recorder.hasFailure)

    let xmlURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).xml"
    )
    defer { try? FileManager.default.removeItem(at: xmlURL) }

    try recorder.writeXML(environment: ["XML_OUTPUT_FILE": xmlURL.path])

    let xml = try String(contentsOf: xmlURL, encoding: .utf8)
    #expect(xml.contains("<testsuite name=\"MySuite&lt;1&gt;\" status=\"run\""))
    #expect(
      xml.contains(
        "<testcase name=\"testPass\" status=\"run\" result=\"completed\" time=\"0.250\">")
    )
    #expect(xml.contains("<skipped message=\"skipped &quot;reason&quot;\"/>"))
    #expect(
      xml.contains(
        "<failure message=\"expected 1 &lt; 2 &amp; &apos;ok&apos;\"/>"
      )
    )
  }
}

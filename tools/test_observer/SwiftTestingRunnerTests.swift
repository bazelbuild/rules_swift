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

import BazelTestObservation
import Testing

struct SwiftTestingRunnerTests {
  @Test(
    arguments: [
      // Schema < 6.3: `isKnown` is a required boolean and there is no `isFailure`.
      (["isKnown": false], false, true),
      (["isKnown": true], true, true),
      // Schema 6.3 and 6.4: `isFailure` and `severity` are present.
      (["isKnown": false, "severity": "error", "isFailure": true], false, true),
      (["isKnown": false, "severity": "warning", "isFailure": false], false, false),
      // Schema >= 6.5: `isKnown` is omitted for unknown issues and may be a comment string.
      (["severity": "error", "isFailure": true], false, true),
      (["isKnown": "flaky on Linux", "severity": "error", "isFailure": false], true, false),
      (["isKnown": true, "severity": "error", "isFailure": false], true, false),
    ] as [([String: JSON], Bool, Bool)]
  )
  func `SwiftTestingRunner classifies issues across JSON schema versions`(
    issue: [String: JSON], isKnown: Bool, isFailing: Bool
  ) {
    #expect(SwiftTestingRunner.isKnownIssue(issue) == isKnown)
    #expect(SwiftTestingRunner.isFailingIssue(issue) == isFailing)
  }

  @Test(
    arguments: [
      // Schema < 6.5: use the `fail` message that swift-testing prints to the console.
      (
        [
          "issue": ["isKnown": false],
          "messages": [
            ["symbol": "fail", "text": "Expectation failed: 1 == 2"],
            ["symbol": "details", "text": "1 == 2 \u{2192} false"],
          ],
        ],
        "Expectation failed: 1 == 2"
      ),
      // Schema >= 6.5: no `messages`, so build the reason from the structured fields.
      (
        [
          "issue": [
            "severity": "error",
            "isFailure": true,
            "expression": ["sourceCode": "1 == 2", "value": "false"],
          ],
          "sourceLocation": [
            "filePath": "foo/bar/FailingTest.swift",
            "fileID": "Module/FailingTest.swift",
            "line": 4,
            "column": 3,
          ],
          "comments": ["math is broken"],
        ],
        "Issue recorded at FailingTest.swift:4:3: Expectation failed: 1 == 2 - math is broken"
      ),
      (
        ["issue": ["severity": "error", "isFailure": true, "error": ["description": "MyError()"]]],
        "Issue recorded: Caught error: MyError()"
      ),
    ] as [([String: JSON], String)]
  )
  func `SwiftTestingRunner failure reasons across JSON schema versions`(
    payload: [String: JSON], expectedReason: String
  ) {
    #expect(SwiftTestingRunner.failureReason(for: payload) == expectedReason)
  }
}

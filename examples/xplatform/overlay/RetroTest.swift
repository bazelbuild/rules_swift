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

import OrientationModule
import RetroLibrary
import XCTest

final class RetroTest: XCTestCase {
  var rect: RetroRect!

  override func setUp() {
    rect = RetroRect(x: 1, y: 2, width: 3, height: 4)
  }

  func testRenamedAPI() {
    rect.print()
  }

  func testRefinedAPI() {
    XCTAssertEqual(rect.area, 12.0, accuracy: 0.001)
  }

  func testDeclarationAddedInOverlay() {
    XCTAssertEqual(rect.description, "<x: 1.0, y: 2.0, width: 3.0, height: 4.0>")
  }

  func testDeclarationUsingTypeOnlyImportedByOverlay() {
    XCTAssertEqual(rect.orientation, .vertical)
  }
}

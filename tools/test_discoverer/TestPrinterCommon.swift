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

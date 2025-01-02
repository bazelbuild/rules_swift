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

import BazelRunfiles

let runfiles = try Runfiles.create()

// Runfiles lookup paths have the form `my_workspace/package/file`.
// Runfiles path lookup may return nil.
guard let runFile = runfiles.rlocation("build_bazel_rules_swift/examples/runfiles/data/sample.txt") else {
    fatalError("couldn't resolve runfile")
}

print(runFile)

// Runfiles path lookup may return a non-existent path.
let content = try String(contentsOfFile: runFile, encoding: .utf8)

assert(content == "Hello runfiles")
print(content)

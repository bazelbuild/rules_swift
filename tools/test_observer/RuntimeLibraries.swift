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

/// Dynamically load the testing libraries needed by the test observer.
///
/// On Apple platforms, we weakly link against XCTest.framework, the XCTest Swift support dylib, and
/// Testing.framework because the machine that links the test binary might not be the same that runs
/// it, and they might have Xcode installed at different paths. To handle this, we find the path
/// that Bazel says Xcode they're installed at on the machine where the test is running and load
/// them dynamically.
@MainActor
public func loadTestingLibraries() throws {
  #if os(Linux)
    // Nothing to do here. All dependencies, including testing frameworks, are statically linked.
  #else
    guard let sdkRoot = ProcessInfo.processInfo.environment["SDKROOT"] else {
      throw LibraryLoadError("ERROR: Bazel must set the SDKROOT in order to find XCTest")
    }
    let sdkRootURL = URL(fileURLWithPath: sdkRoot)
    let platformDeveloperPath =
      sdkRootURL  // .../Developer/SDKs/MacOSX.sdk
      .deletingLastPathComponent()  // .../Developer/SDKs
      .deletingLastPathComponent()  // .../Developer

    let xcTestPath =
      platformDeveloperPath
      .appendingPathComponent("Library/Frameworks/XCTest.framework/XCTest")
      .path
    guard dlopen(xcTestPath, RTLD_NOW) != nil else {
      throw LibraryLoadError(
        #"""
        ERROR: dlopen("\#(xcTestPath)") failed: \#(String(cString: dlerror()))
        """#)
    }

    // In versions of Xcode that have Testing.framework (Xcode 16 and above),
    // libXCTestSwiftSupport.dylib links to it so we need to load the former first. We allow this to
    // fail silently, however, to maintain compatibility with older versions of Xcode (where it
    // doesn't exist, and thus the support library doesn't use it).
    let testingPath =
      platformDeveloperPath
      .appendingPathComponent("Library/Frameworks/Testing.framework/Testing")
      .path
    _ = dlopen(testingPath, RTLD_NOW)

    let xcTestSwiftSupportPath =
      platformDeveloperPath
      .appendingPathComponent("usr/lib/libXCTestSwiftSupport.dylib")
      .path
    guard dlopen(xcTestSwiftSupportPath, RTLD_NOW) != nil else {
      throw LibraryLoadError(
        #"""
        ERROR: dlopen("\#(xcTestSwiftSupportPath)") failed: \#(String(cString: dlerror()))
        """#)
    }
  #endif
}

/// An error that is thrown when a runtime library cannot be loaded.
struct LibraryLoadError: Swift.Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

/// We call this from the generated `main` so that we can declare it non-async (to make XCTest
/// happy) but then safely wait for an async task (swift-testing) to complete. This is part of the
/// concurrency ABI, so it can't realistically change much in the future.
@_silgen_name("swift_task_asyncMainDrainQueue")
public func _asyncMainDrainQueue() -> Swift.Never

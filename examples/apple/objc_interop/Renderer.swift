// Copyright 2018 The Bazel Authors. All rights reserved.
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

@objc(SnapRenderer)
public class Renderer: NSObject {

  private let prefix: String

  @objc public init(prefix: NSString) {
    self.prefix = prefix as String
  }

  @objc public func printHaHa(_ message: NSString) {
    print("\(prefix)\(message)")
  }

}

@objc(SnapRenderProtocol)
public protocol RenderProtocol: NSObjectProtocol {

    func render(_ name: String)
}
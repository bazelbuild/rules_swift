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
import examples_apple_objc_interop_PrintStream
import Renderer

@objc(OIPrinter)
public class Printer: NSObject {

  private let stream: OIPrintStream
  private let prefix: String
  private let renderer: Renderer

  @objc public init(prefix: NSString) {
    self.stream = OIPrintStream(fileHandle: .standardOutput)
    self.prefix = prefix as String
    self.renderer = Renderer(prefix:prefix)
  }

  @objc public func print(_ message: NSString) {
    stream.print("\(prefix)\(message)")
  }

  @objc public func print2(_ message: NSString, renderer: Renderer) {
    stream.print("\(prefix)\(message)")
  }
}

extension Printer: RenderProtocol { 
  public func render(_ name: String) {
    stream.print(name)
  }
}
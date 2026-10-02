// Copyright 2022 The Bazel Authors. All rights reserved.
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

/// Structured information about test classes and methods discovered by scanning symbol graphs.
package struct DiscoveredTests {
  /// The modules containing test classes/methods that were discovered in the symbol graph, keyed by
  /// the module name.
  package var modules: [String: Module] = [:]
}

extension DiscoveredTests {
  /// Information about a module discovered in the symbol graphs that contains tests.
  package struct Module {
    /// The name of the module.
    package var name: String

    /// The `XCTestCase`-inheriting classes (or extensions to `XCTestCase`-inheriting classes) in
    /// the module, keyed by the class name.
    package var classes: [String: Class] = [:]
  }
}

extension DiscoveredTests {
  /// Information about a class or class extension discovered in the symbol graphs that inherits
  /// (directly or indirectly) from `XCTestCase`.
  package struct Class {
    /// The name of the `XCTestCase`-inheriting class.
    package var name: String

    /// The methods that were discovered in the class to represent tests.
    package var methods: [Method] = []
  }
}

extension DiscoveredTests {
  /// Information about a discovered test method in an `XCTestCase` subclass.
  package struct Method {
    /// The name of the discovered test method.
    package var name: String

    /// Indicates whether the test method was declared `async` or not.
    package var isAsync: Bool
  }
}

// Copyright 2019 The Bazel Authors. All rights reserved.
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

/// Encapsulates the wall, user, and sys clock times of a process's execution.
struct Timing: Comparable {
  /// Total wall clock time.
  var wall: TimeInterval

  /// Amount of time spent in user-mode code.
  var user: TimeInterval

  /// Amount of time spent in kernel code.
  var sys: TimeInterval

  static func < (lhs: Timing, rhs: Timing) -> Bool {
    return lhs.wall < rhs.wall
  }

  /// Creates a new timing with the given values.
  init(wall: TimeInterval = 0, user: TimeInterval = 0, sys: TimeInterval = 0) {
    self.wall = wall
    self.user = user
    self.sys = sys
  }

  /// Gets or sets one of the clock values in this timing.
  ///
  /// - Parameter key: The timing to update. Must be `"wall"`, `"user"`, or `"sys"`.
  subscript(key: String) -> Double {
    get { return self[keyPath: keyPath(for: key)] }
    set {
      let keyPath = self.keyPath(for: key)
      self[keyPath: keyPath] = newValue
    }
  }

  /// Gets a keypath that can be used to get or set the given timing.
  ///
  /// - Precondition: `name` must be `"wall"`, `"user"`, or `"sys"`.
  private func keyPath(for name: String) -> WritableKeyPath<Timing, Double> {
    switch name {
    case "wall": return \.wall
    case "user": return \.user
    case "sys": return \.sys
    default: fatalError("Unknown timing '\(name)'")
    }
  }
}

/// Statistics about an invocation of the Swift frontend.
struct FrontendStats {
  /// The name of the Swift module being compiled.
  let moduleName: String

  /// The source file being compiled, or `"all"` if the invocation involved multiple files.
  let sourceFile: String

  /// The start time of frontend invocation.
  let startTime: Date

  /// The timings of various tasks (such as type checking, code generation, etc.) that occurred
  /// during compilation.
  private(set) var taskTimings = [String: Timing]()

  /// The total timing of the frontend invocation.
  private(set) var frontendTiming = Timing()

  /// The timings of various tasks sorted such that the slowest ones are first.
  func sortedTaskTimings(interestingOnly: Bool) -> [(String, Timing)] {
    var allTimings = Array(taskTimings)

    if interestingOnly {
      allTimings = allTimings.filter {
        switch $0.0 {
        case "AST verification",
          "Name binding",
          "LLVM pipeline",
          "Parsing",
          "Serialization, swiftdoc",
          "Serialization, swiftmodule",
          "SILGen",
          "SIL optimization",
          "SIL verification, post-optimization",
          "SIL verification, pre-optimization",
          "Type checking and Semantic analysis":
          return true
        default: return false
        }
      }
    }

    allTimings.sort { $0.1.wall > $1.1.wall }
    return allTimings
  }

  /// Creates a new `FrontendStats` with information from the given JSON report.
  ///
  /// - Parameter url: A URL to the frontend report JSON file.
  /// - Throws: If there was an error reading or decoding the report.
  init(contentsOf url: URL) throws {
    let reportData = try Data(contentsOf: url)
    let jsonDictionary = try JSONSerialization.jsonObject(with: reportData) as! [String: Any]

    let pathParts = url.lastPathComponent.split(separator: "-")
    self.moduleName = String(pathParts[4])
    self.sourceFile = String(pathParts[5])
    self.startTime = Date(timeIntervalSince1970: TimeInterval(pathParts[1])! / 10e9)

    for (key, value) in jsonDictionary {
      let keyParts = key.split(separator: ".")

      if key.hasPrefix("time.swift.") {
        let category = String(keyParts[2])
        let timingName = String(keyParts[3])
        self.taskTimings[category, default: Timing()][timingName] = value as! Double
      } else if key.hasPrefix("time.swift-frontend.") {
        // The filename and target triple embedded in this string might contain dots, which screws
        // up our string splitting. Instead, we can just get the last component.
        let timingName = String(keyParts.last!)
        self.frontendTiming[timingName] = value as! Double
      }
    }
  }
}

/// Statistics about an invocation of the Swift compiler driver.
struct DriverStats {
  /// The name of the Swift module being compiled.
  let moduleName: String

  /// The start time of the driver invocation.
  let startTime: Date

  /// The total timing of the driver invocation.
  private(set) var driverTiming = Timing()

  /// Creates a new `DriverStats` with information from the given JSON report.
  ///
  /// - Parameter url: A URL to the driver report JSON file.
  /// - Throws: If there was an error reading or decoding the report.
  init(contentsOf url: URL) throws {
    let reportData = try Data(contentsOf: url)
    let jsonDictionary = try JSONSerialization.jsonObject(with: reportData) as! [String: Any]

    let pathParts = url.lastPathComponent.split(separator: "-")
    self.moduleName = String(pathParts[4])
    self.startTime = Date(timeIntervalSince1970: TimeInterval(pathParts[1])! / 10e9)

    for (key, value) in jsonDictionary {
      let keyParts = key.split(separator: ".")

      if key.hasPrefix("time.swift-driver.") {
        // The filename and target triple embedded in this string might contain dots, which screws
        // up our string splitting. Instead, we can just get the last component.
        let timingName = String(keyParts.last!)
        self.driverTiming[timingName] = value as! Double
      }
    }
  }
}

/// Returns a formatted string for the given time interval, appropriate for tabular output.
func formattedSeconds(_ value: TimeInterval) -> String {
  return String(format: "%8.3fs", value)
}

/// Processes the reports described in the manifest file and outputs formatted tables to standard
/// output.
func processReports(fromManifest url: URL) throws {
  let manifestContents = try String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines)
  let reportPaths = manifestContents.split(separator: "\n")

  var allDriverStats = [DriverStats]()
  var allFrontendStats = [String: [FrontendStats]]()

  for reportPath in reportPaths.lazy.map(String.init) {
    let reportURL = URL(fileURLWithPath: reportPath)
    if reportPath.contains("swift-driver") {
      let stats = try DriverStats(contentsOf: reportURL)
      allDriverStats.append(stats)
    } else if reportPath.contains("swift-frontend") {
      let stats = try FrontendStats(contentsOf: reportURL)
      allFrontendStats[stats.moduleName, default: []].append(stats)
    }
  }

  // Sort the driver stats so that the slowest compiles come first.
  allDriverStats.sort { $0.driverTiming.wall > $1.driverTiming.wall }

  for driverStats in allDriverStats {
    let totalDriverTime = String(format: "%0.3fs", driverStats.driverTiming.wall)
    print("# Driver invocation for module \(driverStats.moduleName) (\(totalDriverTime))")
    print()

    guard var frontendStatsForModule = allFrontendStats[driverStats.moduleName] else { continue }
    frontendStatsForModule.sort { $0.frontendTiming.wall > $1.frontendTiming.wall }

    for frontendStats in frontendStatsForModule {
      let totalFrontendTime = String(format: "%0.3fs", frontendStats.frontendTiming.wall)
      print(
        """
        ## Frontend invocation for \
        \(frontendStats.moduleName)/\(frontendStats.sourceFile) \
        (\(totalFrontendTime))
        """)
      print()
      print("| Task                                | Wall      | User      | Sys       |")
      print("| ----------------------------------- | --------- | --------- | --------- |")

      for (category, taskTiming) in frontendStats.sortedTaskTimings(interestingOnly: true) {
        let formattedCategory = category.padding(toLength: 35, withPad: " ", startingAt: 0)
        let formattedWall = formattedSeconds(taskTiming.wall)
        let formattedUser = formattedSeconds(taskTiming.user)
        let formattedSys = formattedSeconds(taskTiming.sys)
        print("| \(formattedCategory) | \(formattedWall) | \(formattedUser) | \(formattedSys) |")
      }

      print()
    }
  }
}

guard CommandLine.arguments.count == 2 else {
  print("USAGE: stats_processor <manifest file>")
  exit(1)
}

let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
try processReports(fromManifest: manifestURL)

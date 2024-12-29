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

import BazelCxxRunfiles
import Foundation

enum RunfilesError: Error {
  case runtimeError(String)
  case unknown
}

typealias RunfilesHandle = UnsafeMutableRawPointer

/// Returns the runtime location of runfiles.
///
/// Runfiles are data-dependencies of Bazel-built binaries and tests.
public final class Runfiles {

  private var handle: RunfilesHandle

  private init(handle: RunfilesHandle) {
    self.handle = handle
  }

  // MARK: API

  /// Returns the runtime path of a runfile.
  ///
  /// Runfiles are data-dependencies of Bazel-built binaries and tests.
  ///
  /// The returned path may not exist. The caller should verify the path's
  /// validity and existence.
  ///
  /// - Parameters:
  ///   - path: runfiles-root-relative path of the runfile
  ///   - sourceRepository: the canonical name of the repository whose
  ///     repository mapping should be used to resolve apparent to canonical
  ///     repository names in `path`. If not provided (default), the
  ///     repository mapping of the repository containing the caller of this
  ///     method is used.
  public func rlocation(_ path: String, sourceRepository: String? = nil) -> String? {
    let result: UnsafeMutablePointer<CChar> = if let sourceRepository {
      Runfiles_RlocationFrom(handle, path, sourceRepository)
    } else {
      Runfiles_Rlocation(handle, path)
    }
    return result.pointee == 0 ? nil : String(cString: result)
  }

  /// Returns additional environment variables to pass to subprocesses.
  ///
  /// Pass these variables to Bazel-built binaries so they can find their
  /// runfiles as well.
  public func envVars() -> [String: String] {
    var size = 0
    guard let cPairs = Runfiles_EnvVars(handle, &size) else {
      return [:]
    }

    var result: [String: String] = [:]
    // Process the char **: even = key, odd = value
    for i in stride(from: 0, to: size, by: 2) {
      guard let keyPointer = cPairs[i], let valuePointer = cPairs[i + 1] else {
        break
      }
      result[String(cString: keyPointer)] = String(cString: valuePointer)

      free(keyPointer)
      free(valuePointer)
    }
    free(cPairs)

    return result
  }

  /// Returns a Runfiles instance identical to the current one, except that it
  /// uses the given repository's repository mapping when resolving runfiles
  /// paths.
  public func with(sourceRepository: String) -> Runfiles {
    Runfiles(handle: Runfiles_WithSourceRepository(handle, sourceRepository))
  }

  // MARK: Factory methods

  /// Returns a new `Runfiles`` instance.
  ///
  /// This method looks at the RUNFILES_MANIFEST_FILE and RUNFILES_DIR
  /// environment variables. If either is empty, the method looks for the
  /// manifest or directory using the other environment variable, or using
  /// CommandLine.arguments[0] under the hood.
  ///
  /// - Parameters:
  ///   - sourceRepository: the canonical name of the repository whose
  ///     repository mapping should be used to resolve apparent to canonical
  ///     repository names in `path` provided to `rlocation`.
  ///     Should be left unset unless you need to pass down a runfiles instance
  ///     into a separate library that needs to do its own lookups with it.
  ///   - callerFilePath: This parameter should never be set as it relies on
  ///     Swift callsite built-in macro expansion to retrieve the file path of
  ///     the caller function that called this factory method and auto deduce
  ///     the canonical repository name of the repository of that calling
  ///     function.
  public static func create(
    sourceRepository: String? = nil,
    _ callerFilePath: String = #filePath
  )
    throws -> Runfiles {
    try createInternal { error in
      Runfiles_Create(CommandLine.arguments[0], sourceRepository ?? Self.repository(from: callerFilePath), error)
    }
  }

  /// Returns a new `Runfiles` instance.
  ///
  /// Use this from any `swift_*` rule if you want to manually specify the paths
  /// to the runfiles manifest and/or runfiles directory.
  ///
  /// This method is the same as `Runfiles.create(sourceRepository:_)`, except
  /// it uses `runfilesManifestFile` and `runfilesDir` as the corresponding
  /// environment variable values, instead of looking up the actual environment
  /// variables.
  public static func create(
    runfilesManifestFile: String,
    runfilesDir: String,
    sourceRepository: String? = nil,
    _ callerFilePath: String = #filePath
  )
    throws -> Runfiles {
    try createInternal { error in
      Runfiles_Create2(
        CommandLine.arguments[0],
        runfilesManifestFile,
        runfilesDir,
        sourceRepository ?? Self.repository(from: callerFilePath),
        error
      )
    }
  }

  // MARK: Helper

  private static func createInternal(
    _ createHandle: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutableRawPointer?
  )
    throws -> Runfiles {
    var error: UnsafeMutablePointer<CChar>? = nil
    guard let handle = createHandle(&error) else {
      if let error {
        let errorStr = String(cString: error)
        free(error)
        throw RunfilesError.runtimeError(errorStr)
      }
      throw RunfilesError.unknown
    }
    return Runfiles(handle: handle)
  }

  // https://github.com/bazel-contrib/rules_go/blob/6505cf2e4f0a768497b123a74363f47b711e1d02/go/runfiles/global.go#L53-L54
  private static let legacyExternalGeneratedFile = /bazel-out\/[^\/]+\/bin\/external\/([^\/]+)/
  private static let legacyExternalFile = /external\/([^\/]+)/

  // Extracts the canonical name of the repository containing the file
  // located at `path`.
  private static func repository(from path: String) -> String {
    if let match = path.prefixMatch(of: legacyExternalGeneratedFile) {
      return String(match.1)
    }
    if let match = path.prefixMatch(of: legacyExternalFile) {
      return String(match.1)
    }
    // If a file is not in an external repository, return an empty string
    return ""
  }

  // MARK: deinit

  deinit {
    Runfiles_Destroy(handle)
  }
}

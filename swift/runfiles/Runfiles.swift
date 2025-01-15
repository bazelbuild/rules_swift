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

protocol LookupStrategy {
    func rlocationChecked(path: String) -> URL?
    func envVars() -> [String: String]
}

struct DirectoryBased: LookupStrategy {

    private let runfilesRoot: URL
    init(path: URL) {
        runfilesRoot = path
    }

    func rlocationChecked(path: String) -> URL? {
        runfilesRoot.appendingPathComponent(path)
    }

    func envVars() -> [String: String] {
        [
            "RUNFILES_DIR": runfilesRoot.path,
        ]
    }
}

struct ManifestBased: LookupStrategy {

    private let manifestPath: URL
    private let runfiles: [String: String]

    init(manifestPath: URL) throws {
        self.manifestPath = manifestPath
        runfiles = try Self.loadRunfiles(from: manifestPath)
    }

    func rlocationChecked(path: String) -> URL? {
        if let runfile = runfiles[path] {
            return URL(fileURLWithPath: runfile)
        }

        // Search for prefixes in the path
        for end in path.indices.reversed() where path[end] == "/" {
            let prefix = String(path[..<end])
            if let prefixMatch = runfiles[prefix] {
                let relativePath = String(path[path.index(after: end)...])
                return URL(fileURLWithPath: prefixMatch + "/" + relativePath)
            }
        }

        return nil
    }

    func envVars() -> [String: String] {
        [
            "RUNFILES_MANIFEST_FILE": manifestPath.path,
        ]
    }

    static func loadRunfiles(from manifestPath: URL) throws -> [String: String] {
        guard let fileHandle = try? FileHandle(forReadingFrom: manifestPath) else {
            throw RunfilesError.missingManifest
        }
        defer {
            try? fileHandle.close()
        }

        var pathMapping = [String: String]()
        if let data = try? fileHandle.readToEnd(), let content = String(data: data, encoding: .utf8) {
            let lines = content.split(separator: "\n")
            for line in lines {
                let fields = line.split(separator: " ", maxSplits: 1)
                if fields.count == 1 {
                    pathMapping[String(fields[0])] = String(fields[0])
                } else {
                    pathMapping[String(fields[0])] = String(fields[1])
                }
            }
        }

        return pathMapping
    }
}

struct RepoMappingKey: Hashable {
    let sourceRepoCanonicalName: String
    let targetRepoApparentName: String
}

public enum RunfilesError: Error {
    case invalidRunfilesLocations
    case missingRunfilesLocations
    case invalidRepoMappingEntry(line: String)
    case missingManifest
}

public final class Runfiles {

    private let strategy: LookupStrategy
    // Value is the runfiles directory of target repository
    private let repoMapping: [RepoMappingKey: String]
    private let sourceRepository: String

    init(strategy: LookupStrategy, repoMapping: [RepoMappingKey: String], sourceRepository: String) {
        self.strategy = strategy
        self.repoMapping = repoMapping
        self.sourceRepository = sourceRepository
    }

    public func rlocation(_ path: String, sourceRepository: String? = nil) -> URL? {
        guard 
            !path.hasPrefix("../"),
            !path.contains("/.."),
            !path.hasPrefix("./"),
            !path.contains("/./"),
            !path.hasSuffix("/."),
            !path.contains("//") 
        else {
            return nil
        }
        guard path.first != "\\" else {
            return nil
        }
        guard path.first != "/" else {
            return URL(fileURLWithPath: path)
        }

        let sourceRepository = sourceRepository ?? self.sourceRepository

        // Split off the first path component, which contains the repository
        // name (apparent or canonical).
        let components = path.split(separator: "/", maxSplits: 1)
        let targetRepository = String(components[0])
        let key = RepoMappingKey(sourceRepoCanonicalName: sourceRepository, targetRepoApparentName: targetRepository)

        if components.count == 1 || repoMapping[key] == nil {
            // One of the following is the case:
            // - not using Bzlmod, so the repository mapping is empty and
            //   apparent and canonical repository names are the same
            // - target_repo is already a canonical repository name and does not
            //   have to be mapped.
            // - path did not contain a slash and referred to a root symlink,
            //   which also should not be mapped.
            return strategy.rlocationChecked(path: path)
        }

        let remainingPath = String(components[1])

        // target_repo is an apparent repository name. Look up the corresponding
        // canonical repository name with respect to the current repository,
        // identified by its canonical name.
        if let targetCanonical = repoMapping[key] {
            return strategy.rlocationChecked(path: targetCanonical + "/" + remainingPath)
        } else {
            return strategy.rlocationChecked(path: path)
        }
    }

    public func envVars() -> [String: String] {
        strategy.envVars()
    }

    // MARK: Factory method

    public static func create(sourceRepository: String? = nil, environment: [String: String]? = nil, _ callerFilePath: String = #filePath) throws -> Runfiles {

        let environment = environment ?? ProcessInfo.processInfo.environment

        let runfilesPath = try computeRunfilesPath(
            argv0: CommandLine.arguments[0],
            manifestFile: environment["RUNFILES_MANIFEST_FILE"],
            runfilesDir: environment["RUNFILES_DIR"],
            isRunfilesManifest: { file in FileManager.default.fileExists(atPath: file) },
            isRunfilesDirectory: { file in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: file, isDirectory: &isDir) && isDir.boolValue
            }
        )

        let strategy: LookupStrategy = switch (runfilesPath) {
            case .manifest(let path):
                try ManifestBased(manifestPath: URL(fileURLWithPath: path))
            case .directory(let path):
                DirectoryBased(path: URL(fileURLWithPath: path))
        }

        // If the repository mapping file can't be found, that is not an error: We
        // might be running without Bzlmod enabled or there may not be any runfiles.
        // In this case, just apply an empty repo mapping.
        let repoMapping = try strategy.rlocationChecked(path: "_repo_mapping").map { path in
            try parseRepoMapping(path: path)
        } ?? [:]

        return Runfiles(strategy: strategy, repoMapping: repoMapping, sourceRepository: sourceRepository ?? repository(from: callerFilePath))
    }

}

  // https://github.com/bazel-contrib/rules_go/blob/6505cf2e4f0a768497b123a74363f47b711e1d02/go/runfiles/global.go#L53-L54
  private let legacyExternalGeneratedFile = /bazel-out\/[^\/]+\/bin\/external\/([^\/]+)/
  private let legacyExternalFile = /external\/([^\/]+)/

  // Extracts the canonical name of the repository containing the file
  // located at `path`.
  private func repository(from path: String) -> String {
    if let match = path.prefixMatch(of: legacyExternalGeneratedFile) {
      return String(match.1)
    }
    if let match = path.prefixMatch(of: legacyExternalFile) {
      return String(match.1)
    }
    // If a file is not in an external repository, return an empty string
    return ""
  }

// MARK: Runfiles Paths Computation

enum RunfilesPath: Equatable {
    case manifest(String)
    case directory(String)
}

func computeRunfilesPath(
    argv0: String,
    manifestFile: String?,
    runfilesDir: String?,
    isRunfilesManifest: (String) -> Bool,
    isRunfilesDirectory: (String) -> Bool
) throws -> RunfilesPath {
    // if a manifest or a runfiles dir was provided, try to use whichever
    // was valid or else error.
    if (manifestFile != nil || runfilesDir != nil) {
        if let manifestFile, isRunfilesManifest(manifestFile) {
            return RunfilesPath.manifest(manifestFile)
        } else if let runfilesDir, isRunfilesDirectory(runfilesDir) {
            return RunfilesPath.directory(runfilesDir)
        } else {
            throw RunfilesError.invalidRunfilesLocations
        }
    }

    // If a manifest exists in one of the well known location, use it.
    for wellKnownManifestFileSuffixes in [".runfiles/MANIFEST", ".runfiles_manifest"] {
        let manifestFileCandidate = "\(argv0)\(wellKnownManifestFileSuffixes)"
        if isRunfilesManifest(manifestFileCandidate) {
            return RunfilesPath.manifest(manifestFileCandidate)
        }
    }

    // If a runfiles dir exists in the well known location, use it.
    let runfilesDirCandidate = "\(argv0).runfiles"
    if isRunfilesDirectory(runfilesDirCandidate) {
        return RunfilesPath.directory(runfilesDirCandidate)
    }

    throw RunfilesError.missingRunfilesLocations
}

// MARK: Parsing Repo Mapping

func parseRepoMapping(path: URL) throws -> [RepoMappingKey: String] {
    guard let fileHandle = try? FileHandle(forReadingFrom: path) else {
        // If the repository mapping file can't be found, that is not an error: We
        // might be running without Bzlmod enabled or there may not be any runfiles.
        // In this case, just apply an empty repo mapping.
        return [:]
    }
    defer {
        try? fileHandle.close()
    }

    var repoMapping = [RepoMappingKey: String]()
    if let data = try fileHandle.readToEnd(), let content = String(data: data, encoding: .utf8) {
        let lines = content.split(separator: "\n")
        for line in lines {
            let fields = line.components(separatedBy: ",")
            if fields.count != 3 {
                throw RunfilesError.invalidRepoMappingEntry(line: String(line))
            }
            let key = RepoMappingKey(
                sourceRepoCanonicalName: fields[0],
                targetRepoApparentName: fields[1]
            )
            repoMapping[key] = fields[2] // mapping
        }
    }

    return repoMapping
}

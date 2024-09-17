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
        runfilesRoot.appending(path: path)
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
            return URL(filePath: runfile)
        }

        // Search for prefixes in the path
        var prefixEnd = path.lastIndex(of: "/")

        while true {
            guard let end = prefixEnd else {
                return nil
            }

            let prefix = String(path[..<end])
            if let prefixMatch = runfiles[prefix] {
                let relativePath = String(path[path.index(after: end)...])
                return URL(filePath: prefixMatch + "/" + relativePath)
            }
            prefixEnd = path[..<end].lastIndex(of: "/")
        }
    }

    func envVars() -> [String: String] {
        let runfilesDir = Self.getRunfilesDir(fromManifestPath: manifestPath)
        return [
            "RUNFILES_MANIFEST_FILE": manifestPath.path,
            "RUNFILES_DIR": runfilesDir?.path ?? "",
        ]
    }

    static func getRunfilesDir(fromManifestPath path: URL) -> URL? {
        let lastComponent = path.lastPathComponent

        if lastComponent == "MANIFEST" {
            return path.deletingLastPathComponent()
        }
        if lastComponent.hasSuffix(".runfiles_manifest") {
            let newPath = path.deletingLastPathComponent().appendingPathComponent(
                path.lastPathComponent.replacingOccurrences(of: "_manifest", with: "")
            )
            return newPath
        }
        return nil
    }

    static func loadRunfiles(from manifestPath: URL) throws -> [String: String] {
        guard let fileHandle = try? FileHandle(forReadingFrom: manifestPath) else {
            throw RunfilesError.error
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
    case error
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
        guard !path.hasPrefix("../"),
              !path.contains("/.."),
              !path.hasPrefix("./"),
              !path.contains("/./"),
              !path.hasSuffix("/."),
              !path.contains("//") else {
            return nil
        }
        guard path.first != "\\" else {
            return nil
        }
        guard path.first != "/" else {
            return URL(filePath: path)
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

    public static func create(sourceRepository: String, environment: [String: String]? = nil) throws -> Runfiles {

        let environment = environment ?? ProcessInfo.processInfo.environment

        let strategy: LookupStrategy
        if let manifestFile = environment["RUNFILES_MANIFEST_FILE"] {
            strategy = try ManifestBased(manifestPath: URL(filePath: manifestFile))
        } else {
            strategy = try DirectoryBased(path: findRunfilesDir(environment: environment))
        }

        // If the repository mapping file can't be found, that is not an error: We
        // might be running without Bzlmod enabled or there may not be any runfiles.
        // In this case, just apply an empty repo mapping.
        let repoMapping = try strategy.rlocationChecked(path: "_repo_mapping").map { repoMappingFile in
            try parseRepoMapping(path: repoMappingFile)
        } ?? [:]

        return Runfiles(strategy: strategy, repoMapping: repoMapping, sourceRepository: sourceRepository)
    }

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
    if let data = try? fileHandle.readToEnd(), let content = String(data: data, encoding: .utf8) {
        let lines = content.split(separator: "\n")
        for line in lines {
            let fields = line.components(separatedBy: ",")
            if fields.count != 3 {
                throw RunfilesError.error
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

// MARK: Finding Runfiles Directory

func findRunfilesDir(environment: [String: String]) throws -> URL {
    if let runfilesDirPath = environment["RUNFILES_DIR"] {
        let runfilesDirURL = URL(filePath: runfilesDirPath)
        if FileManager.default.fileExists(atPath: runfilesDirURL.path, isDirectory: nil) {
            return runfilesDirURL
        }
    }

    if let testSrcdirPath = environment["TEST_SRCDIR"] {
        let testSrcdirURL = URL(filePath: testSrcdirPath)
        if FileManager.default.fileExists(atPath: testSrcdirURL.path, isDirectory: nil) {
            return testSrcdirURL
        }
    }

    // Consume the first argument (argv[0])
    guard let execPath = CommandLine.arguments.first else {
        throw RunfilesError.error
    }

    var binaryPath = URL(filePath: execPath)

    while true {
        // Check for our neighboring $binary.runfiles directory.
        let runfilesName = binaryPath.lastPathComponent + ".runfiles"
        let runfilesPath = binaryPath.deletingLastPathComponent().appendingPathComponent(runfilesName)

        if FileManager.default.fileExists(atPath: runfilesPath.path, isDirectory: nil) {
            return runfilesPath
        }

        // Check if we're already under a *.runfiles directory.
        var ancestorURL = binaryPath.deletingLastPathComponent()
        while ancestorURL.path != "/" {
            if ancestorURL.lastPathComponent.hasSuffix(".runfiles") {
                return ancestorURL
            }
            ancestorURL.deleteLastPathComponent()
        }

        // Check if it's a symlink and follow it.
        if let symlinkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: binaryPath.path) {
            let linkTargetURL = URL(
                fileURLWithPath: symlinkTarget,
                relativeTo: binaryPath.deletingLastPathComponent()
            )
            binaryPath = linkTargetURL
        } else {
            break
        }
    }

    throw RunfilesError.error
}

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

    init(manifestPath: URL) {
        self.manifestPath = manifestPath
        runfiles = Self.loadRunfiles(from: manifestPath)
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
        guard let runfilesDir = Self.getRunfilesDir(fromManifestPath: manifestPath) else {
            return [:]
        }
        return [
            "RUNFILES_MANIFEST_FILE": manifestPath.path,
            "RUNFILES_DIR": runfilesDir.path,
        ]
    }

    static func getRunfilesDir(fromManifestPath path: URL) -> URL? {
        let lastComponent = path.lastPathComponent

        if lastComponent == "MANIFEST" {
            return path.deletingLastPathComponent()
        }
        if lastComponent == ".runfiles_manifest" {
            let newPath = path.deletingLastPathComponent().appendingPathComponent(
                path.lastPathComponent.replacingOccurrences(of: "_manifest", with: "")
            )
            return newPath
        }
        return nil
    }

    static func loadRunfiles(from manifestPath: URL) -> [String: String] {
        guard let fileHandle = try? FileHandle(forReadingFrom: manifestPath) else {
            // If the file doesn't exist, return an empty dictionary.
            return [:]
        }
        defer {
            try? fileHandle.close()
        }

        var pathMapping = [String: String]()
        if let data = try? fileHandle.readToEnd(), let content = String(data: data, encoding: .utf8) {
            let lines = content.split(separator: "\n")
            for line in lines {
                let fields = line.components(separatedBy: " ")
                if fields.count == 1 {
                    pathMapping[fields[0]] = fields[0]
                } else {
                    pathMapping[fields[0]] = fields[1]
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

    // Value is the runfiles directory of target repository
    private let repoMapping: [RepoMappingKey: String]
    private let strategy: LookupStrategy

    init(strategy: LookupStrategy, repoMapping: [RepoMappingKey: String]) {
        self.strategy = strategy
        self.repoMapping = repoMapping
    }

    public func rlocation(_ path: String, sourceRepository: String) -> URL? {
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

        // Split off the first path component, which contains the repository
        // name (apparent or canonical).
        let components = path.split(separator: ",", maxSplits: 1)
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
        let targetCanonical = repoMapping[key]
        return strategy.rlocationChecked(path: targetRepository + "/" + remainingPath)
    }

    public func envVars() -> [String: String] {
        strategy.envVars()
    }

    // MARK: Factory method

    public static func create(environment: [String: String]? = nil) throws -> Runfiles? {

        let environment = environment ?? ProcessInfo.processInfo.environment

        let strategy: LookupStrategy
        if let manifestFile = environment["RUNFILES_MANIFEST_FILE"] {
            strategy = ManifestBased(manifestPath: URL(filePath: manifestFile))
        } else {
            strategy = try DirectoryBased(path: findRunfilesDir())
        }

        // If the repository mapping file can't be found, that is not an error: We
        // might be running without Bzlmod enabled or there may not be any runfiles.
        // In this case, just apply an empty repo mapping.
        let repoMapping = try strategy.rlocationChecked(path: "_repo_mapping").map { repoMappingFile in
            try parseRepoMapping(path: repoMappingFile)
        } ?? [:]

        return Runfiles(strategy: strategy, repoMapping: repoMapping)
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
            repoMapping[key] = fields[2]
        }
    }

    return repoMapping
}

// MARK: Finding Runfiles Directory

func findRunfilesDir() throws -> URL {
    if let runfilesDirPath = ProcessInfo.processInfo.environment["RUNFILES_DIR"],
       let runfilesDirURL = URL(string: runfilesDirPath),
       FileManager.default.fileExists(atPath: runfilesDirURL.path, isDirectory: nil) {
        return runfilesDirURL
    }

    if let testSrcdirPath = ProcessInfo.processInfo.environment["TEST_SRCDIR"],
       let testSrcdirURL = URL(string: testSrcdirPath),
       FileManager.default.fileExists(atPath: testSrcdirURL.path, isDirectory: nil) {
        return testSrcdirURL
    }

    // Consume the first argument (argv[0])
    guard let execPath = CommandLine.arguments.first else {
        throw RunfilesError.error
    }

    var binaryPath = URL(fileURLWithPath: execPath)

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

import ArgumentParser
import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#endif

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension FileHandle: @retroactive TextOutputStream {
  public func write(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    self.write(data)
  }
}

// Helper to write to stderr
var standardError = FileHandle.standardError

struct ToolchainDownloader {
  let cacheDir: String?

  private func swiftlyToOpenApiVersion(swiftly_version: String) -> String {
    if swiftly_version.contains("-snapshot-") {
      let parts = swiftly_version.split(separator: "-", maxSplits: 2)
      let branch = parts[0]
      let version = parts[2]
      if branch == "main" {
        return "swift-DEVELOPMENT-SNAPSHOT-\(version)-a"
      }
      return "swift-\(branch)-DEVELOPMENT-SNAPSHOT-\(version)-a"
    }
    return "swift-\(swiftly_version)-RELEASE"
  }

  private func swiftlyVersionToCategory(swiftly_version: String) -> String {
    if swiftly_version.contains("-snapshot-") {
      let parts = swiftly_version.split(separator: "-", maxSplits: 1)
      let branch = parts[0]
      if branch == "main" {
        return "development"
      }
      return "swift-\(branch)-branch"
    }
    return "swift-\(swiftly_version)-release"
  }

  private func getFilename(version: String, platform: String) -> String {
    if platform == "xcode" {
      return "\(version)-osx.pkg"
    }
    return "\(version)-\(platform).tar.gz"
  }

  func getDownloadURL(swift_version: String, platform: String) -> String {
    let version = swiftlyToOpenApiVersion(swiftly_version: swift_version)
    return
      "https://download.swift.org/\(swiftlyVersionToCategory(swiftly_version: swift_version))/\(platform.replacing(".", with: ""))/\(version)/\(getFilename(version: version,platform: platform))"
  }

  private func downloadFile(url: URL) async throws -> Data {
    // Check cache first if cache directory is provided
    if let cacheDir = cacheDir {
      let filename = url.lastPathComponent
      let cachePath = (cacheDir as NSString).appendingPathComponent(filename)

      if FileManager.default.fileExists(atPath: cachePath) {
        print("Found \(filename) in \(cacheDir). Skipping", to: &standardError)
        return try Data(contentsOf: URL(fileURLWithPath: cachePath))
      }
    }
    print("Downloading \(url)...", to: &standardError)

    let (data, response) = try await URLSession.shared.data(from: url)
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
      throw NSError(
        domain: "SwiftReleaseDownloader",
        code: httpResponse.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey:
            "HTTP error \(httpResponse.statusCode) for \(url.absoluteString)"
        ]
      )
    }

    // Save to cache if cache directory is provided
    if let cacheDir = cacheDir {
      let filename = url.lastPathComponent
      let cachePath = (cacheDir as NSString).appendingPathComponent(filename)

      // Create cache directory if it doesn't exist
      try FileManager.default.createDirectory(
        atPath: cacheDir, withIntermediateDirectories: true, attributes: nil)

      // Write data to cache
      try data.write(to: URL(fileURLWithPath: cachePath))
      print("  Cached to: \(cachePath)", to: &standardError)
    }

    return data
  }

  func getSha256(swift_version: String, platform: String) async throws -> String {
    let url = getDownloadURL(swift_version: swift_version, platform: platform)
    guard let url = URL(string: url) else {
      print("Malformed URL: \(url)")
      throw ExitCode.failure
    }
    let data = try await downloadFile(url: url)
    return try sha256(of: data)
  }

  private func sha256(of data: Data) throws -> String {
    #if canImport(CryptoKit)
      let hash = SHA256.hash(data: data)
      return hash.compactMap { String(format: "%02x", $0) }.joined()
    #else
      // CryptoKit is Apple-only. On Linux, shell out to `sha256sum` (part of
      // GNU coreutils, present on every distro we care about). The tool is a
      // maintainer utility run via `bazel run`, so the subprocess overhead is
      // not a concern here.
      let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
      try data.write(to: tempURL)
      defer { try? FileManager.default.removeItem(at: tempURL) }

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["sha256sum", tempURL.path]
      let stdout = Pipe()
      process.standardOutput = stdout
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw NSError(
          domain: "ToolchainDownloader",
          code: Int(process.terminationStatus),
          userInfo: [NSLocalizedDescriptionKey: "sha256sum exited with status \(process.terminationStatus)"]
        )
      }
      let output = stdout.fileHandleForReading.readDataToEndOfFile()
      guard let line = String(data: output, encoding: .utf8),
        let hex = line.split(separator: " ").first
      else {
        throw NSError(
          domain: "ToolchainDownloader",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Could not parse sha256sum output"]
        )
      }
      return String(hex)
    #endif
  }
}

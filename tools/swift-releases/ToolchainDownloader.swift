import ArgumentParser
import CryptoKit
import Foundation

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
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }
}

import ArgumentParser
import CryptoKit
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Helper to write to stderr
var standardError = FileHandle.standardError

extension FileHandle: @retroactive TextOutputStream {
  public func write(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    self.write(data)
  }
}

struct Release: Codable {
  let name: String
  let tag: String
  let xcode: String?
  let xcode_release: Bool?
  let date: String?
  let platforms: [Platform]

  struct Platform: Codable {
    let name: String
    let platform: String
    let docker: String?
    let dir: String?
    let checksum: String?
    let archs: [String]
  }
}

typealias ReleasesResponse = [Release]

func fetchReleases() throws -> ReleasesResponse {
  let url = URL(string: "https://www.swift.org/api/v1/install/releases.json")!
  let semaphore = DispatchSemaphore(value: 0)
  var result: Result<Data, Error>?

  let task = URLSession.shared.dataTask(with: url) { data, response, error in
    if let error = error {
      result = .failure(error)
    } else if let httpResponse = response as? HTTPURLResponse {
      if httpResponse.statusCode != 200 {
        let error = NSError(
          domain: "SwiftReleaseDownloader",
          code: httpResponse.statusCode,
          userInfo: [NSLocalizedDescriptionKey: "HTTP error \(httpResponse.statusCode)"]
        )
        result = .failure(error)
      } else if let data = data {
        result = .success(data)
      } else {
        result = .failure(
          NSError(
            domain: "SwiftReleaseDownloader", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "No data received"]))
      }
    } else if let data = data {
      result = .success(data)
    } else {
      result = .failure(
        NSError(
          domain: "SwiftReleaseDownloader", code: -1,
          userInfo: [NSLocalizedDescriptionKey: "No data received"]))
    }
    semaphore.signal()
  }
  task.resume()
  semaphore.wait()

  let data = try result!.get()
  let decoder = JSONDecoder()
  return try decoder.decode(ReleasesResponse.self, from: data)
}

func downloadFile(url: URL, cacheDir: String?) throws -> Data {
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

  let semaphore = DispatchSemaphore(value: 0)
  var result: Result<Data, Error>?

  let task = URLSession.shared.dataTask(with: url) { data, response, error in
    if let error = error {
      result = .failure(error)
    } else if let httpResponse = response as? HTTPURLResponse {
      if httpResponse.statusCode != 200 {
        let error = NSError(
          domain: "SwiftReleaseDownloader",
          code: httpResponse.statusCode,
          userInfo: [
            NSLocalizedDescriptionKey:
              "HTTP error \(httpResponse.statusCode) for \(url.absoluteString)"
          ]
        )
        result = .failure(error)
      } else if let data = data {
        result = .success(data)
      } else {
        result = .failure(
          NSError(
            domain: "SwiftReleaseDownloader", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "No data received"]))
      }
    } else if let data = data {
      result = .success(data)
    } else {
      result = .failure(
        NSError(
          domain: "SwiftReleaseDownloader", code: -1,
          userInfo: [NSLocalizedDescriptionKey: "No data received"]))
    }
    semaphore.signal()
  }
  task.resume()
  semaphore.wait()

  let data = try result!.get()

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

func sha256(data: Data) -> String {
  let hash = SHA256.hash(data: data)
  return hash.compactMap { String(format: "%02x", $0) }.joined()
}

func getDownloadURL(tag: String, platformName: String) -> String {
  let version = tag
  let category = tag.lowercased()
  let filename: String

  let platformDir = platformName.replacingOccurrences(of: ".", with: "")
  if platformName == "xcode" {
    filename = "\(version)-osx.pkg"
  } else {
    filename = "\(version)-\(platformName).tar.gz"
  }

  return "https://download.swift.org/\(category)/\(platformDir)/\(version)/\(filename)"
}

@main
struct SwiftReleases: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "swift-releases",
    abstract: "A utility for working with Swift releases",
    subcommands: [List.self],
    defaultSubcommand: List.self
  )
}

extension SwiftReleases {
  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Download Swift release archives and print their SHA256 hashes"
    )

    @Argument(help: "The Swift version to download (e.g., 6.0.3)")
    var version: String

    @Option(help: "Directory to cache downloaded archives")
    var cache: String?

    func run() throws {
      let releases = try fetchReleases()

      guard let release = releases.first(where: { $0.name == version }) else {
        print("Error: Version '\(version)' not found", to: &standardError)
        print("Available versions:", to: &standardError)
        for rel in releases.reversed().prefix(20) {
          print("  - \(rel.name)", to: &standardError)
        }
        if releases.count > 20 {
          print("  ... and \(releases.count - 20) more", to: &standardError)
        }
        throw ExitCode.failure
      }

      // Dictionary to store platform -> sha256 mappings
      var checksums: [String: String] = [:]

      // Only Linux & MacOS toolchains are supported for now.
      // Supported Linux toolchains for a given version are in the response,
      // but MacOS toolchains aren't. They're just assumed to be there. So we
      // must add them manually.
      let platforms =
        release.platforms.filter {
          $0.platform == "Linux"
        } + [
          Release.Platform(
            name: "osx",
            platform: "osx",
            docker: nil,
            dir: "xcode",
            checksum: nil,
            archs: ["aarch64"],
          )
        ]

      for platform in platforms {
        // Handle platforms with checksums (like static-sdk, wasm-sdk)
        if let checksum = platform.checksum {
          // For platforms with checksums, use the platform name directly
          let platformKey = platform.platform
          checksums[platformKey] = checksum
          continue
        }

        // Download for each architecture
        for arch in platform.archs {
          let platformName =
            platform.dir ?? platform.name.lowercased().replacingOccurrences(of: " ", with: "")
          let platformKey: String
          if platformName == "xcode" || arch == "x86_64" {
            platformKey = platformName
          } else {
            platformKey = "\(platformName)-\(arch)"
          }

          let downloadURL = getDownloadURL(
            tag: release.tag, platformName: platform.dir ?? platformKey)

          do {
            let url = URL(string: downloadURL)!
            let data = try downloadFile(url: url, cacheDir: cache)
            let hash = sha256(data: data)
            checksums[platformKey] = hash
          } catch {
            print("Error: \(error)", to: &standardError)
            throw error
          }
        }
      }

      // Print in the requested format
      print("    \"\(version)\": {")
      let sortedKeys = checksums.keys.sorted()
      for (index, key) in sortedKeys.enumerated() {
        let comma = index < sortedKeys.count - 1 ? "," : ""
        print("        \"\(key)\": \"\(checksums[key]!)\"\(comma)")
      }
      print("    },")
    }
  }
}

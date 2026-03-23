import ArgumentParser
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@main
struct SwiftReleases: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "swift-releases",
    abstract: "A utility for working with Swift releases",
    subcommands: [List.self],
    defaultSubcommand: List.self
  )
}

func checkUrl(url: String) async throws -> Bool {
  guard let url = URL(string: url) else {
    print("Malformed URL: \(url)")
    throw ExitCode.failure
  }

  var request = URLRequest(url: url)
  request.httpMethod = "HEAD"

  let (_, response) = try await URLSession.shared.data(for: request)

  guard let httpResponse = response as? HTTPURLResponse else { return false }
  return httpResponse.statusCode != 404
}

extension SwiftReleases {
  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Download Swift release archives and print their SHA256 hashes"
    )

    @Argument(help: "The Swift version to download (e.g., 6.0.3)")
    var version: String

    @Option(help: "Directory to cache downloaded archives")
    var cache: String?

    @Option(name: .customLong("platform"), help: "Use the specified platform (required for snapshot toolchains)")
    var platforms: [String] = []

    @Flag(
      help: "Only make sure the URLs are valid. Do not download the archives or calculate the SHA")
    var dryRun: Bool = false

    func run() async throws {
      let downloader = ToolchainDownloader(cacheDir: self.cache)

      var platformKeys = platforms
      if platformKeys.isEmpty {
        if version.contains("-snapshot-") {
          print("Can't detect available platforms for unreleased (snapshot) toolchains. Please use --platform")
          throw ExitCode.validationFailure
        }
        let releasedToolchain = try await ReleasedToolchain(version: self.version)
        platformKeys = releasedToolchain.getPlatformKeys()
      }

      if self.dryRun {
        for platform in platformKeys {
          let url = downloader.getDownloadURL(swift_version: version, platform: platform)
          print("\(try await checkUrl(url: url) ? "OK" : "FAIL")\t\(url)")
        }
        return
      }

      var checksums: [String: String] = [:]
      for platform in platformKeys {
        checksums[platform] = try await downloader.getSha256(
          swift_version: version, platform: platform)
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

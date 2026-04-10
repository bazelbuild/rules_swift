import ArgumentParser
import Foundation

struct ReleasedToolchain {
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

      var platformKeys: [String] {
        let platformName =
          self.dir ?? self.name.lowercased().replacingOccurrences(of: " ", with: "")
        return self.archs.map { arch in
          if platformName == "xcode" || arch == "x86_64" {
            return platformName
          } else {
            return "\(platformName)-\(arch)"
          }
        }
      }
    }
  }

  let release: Release
  let version: String

  typealias ReleasesResponse = [Release]

  init(version: String) async throws {
    let url = URL(string: "https://www.swift.org/api/v1/install/releases.json")!
    let (data, response) = try await URLSession.shared.data(from: url)
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
      throw NSError(
        domain: "SwiftReleaseDownloader",
        code: httpResponse.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "HTTP error \(httpResponse.statusCode)"]
      )
    }
    let releases = try JSONDecoder().decode(ReleasesResponse.self, from: data)

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

    self.release = release
    self.version = version
  }

  func getPlatformKeys() -> [String] {
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
    return platforms.flatMap { $0.platformKeys }
  }
}

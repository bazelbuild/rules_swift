// Copyright 2025 The Bazel Authors. All rights reserved.
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

@testable import BazelRunfiles
import Foundation
import XCTest

// Mainly adapted from https://github.com/bazelbuild/rules_python/blob/main/tests/runfiles/runfiles_test.py
final class RunfilesTests: XCTestCase {
  func testRlocationArgumentValidation() throws {
    let (fileURL, clean) = try createMockFile(name: "MANIFEST", contents: "a/b /c/d"); defer { try? clean() }

    let runfiles = try Runfiles.create(
      environment: [
        "RUNFILES_MANIFEST_FILE": fileURL.path,
        "RUNFILES_DIR": "ignored when RUNFILES_MANIFEST_FILE has a value",
        "TEST_SRCDIR": "always ignored",
      ]
    )
    XCTAssertEqual(try runfiles.rlocation("a/b").path, "/c/d")
    XCTAssertNil(try? runfiles.rlocation("foo"))
  }

  func testManifestBasedRunfilesEnvVarsFromArbitraryManifest() throws {
    let (manifest, clean) = try createMockFile(name: "x_manifest", contents: "a/b /c/d"); defer { try? clean() }

    let runfiles = try Runfiles.create(
      environment: [
        "RUNFILES_MANIFEST_FILE": manifest.path,
        "TEST_SRCDIR": "always ignored",
      ]
    )

    XCTAssertEqual(runfiles.envVars(), [
      "RUNFILES_MANIFEST_FILE": manifest.path,
    ])
  }

  func testCreatesDirectoryBasedRunfiles() throws {
    let (runfilesDir, clean) = try createMockDirectory(name: "my_custom_runfiles"); defer { try? clean() }
    let runfiles = try Runfiles.create(
      environment: [
        "RUNFILES_DIR": runfilesDir.path,
        "TEST_SRCDIR": "always ignored",
      ]
    )

    XCTAssertEqual(try runfiles.rlocation("a/b").path, runfilesDir.path + "/" + "a/b")
    XCTAssertEqual(try runfiles.rlocation("foo").path, runfilesDir.path + "/" + "foo")
  }

  func testCreatesDirectoryBasedRunfilesEnvVars() throws {
    let (runfilesDir, clean) = try createMockDirectory(name: "my_custom_runfiles"); defer { try? clean() }
    let runfiles = try Runfiles.create(
      environment: [
        "RUNFILES_DIR": runfilesDir.path,
        "TEST_SRCDIR": "always ignored",
      ]
    )

    XCTAssertEqual(runfiles.envVars(), [
      "RUNFILES_DIR": runfilesDir.path,
    ])
  }

  func testFailsToCreateManifestBasedBecauseManifestDoesNotExist() {
    XCTAssertNil(try? Runfiles.create(
      environment: ["RUNFILES_MANIFEST_FILE": "non-existing path"]
    ))
  }

  func testManifestBasedRlocation() throws {
    let manifestContents = """
    /Foo/runfile1
    Foo/runfile2 /Actual Path/runfile2
    Foo/Bar/runfile3 /the path/run file 3.txt
    Foo/Bar/Dir /Actual Path/Directory
    """
    let (manifest, clean) = try createMockFile(name: "MANIFEST", contents: manifestContents)
    defer { try? clean() }

    let runfiles = try Runfiles.create(
      environment: [
        "RUNFILES_MANIFEST_FILE": manifest.path,
        "TEST_SRCDIR": "always ignored",
      ]
    )

    XCTAssertEqual(try runfiles.rlocation("/Foo/runfile1").path, "/Foo/runfile1")
    XCTAssertEqual(try runfiles.rlocation("Foo/runfile2").path, "/Actual Path/runfile2")
    XCTAssertEqual(try runfiles.rlocation("Foo/Bar/runfile3").path, "/the path/run file 3.txt")
    XCTAssertEqual(try runfiles.rlocation("Foo/Bar/Dir/runfile4").path, "/Actual Path/Directory/runfile4")
    XCTAssertEqual(
      try runfiles.rlocation("Foo/Bar/Dir/Deeply/Nested/runfile4").path,
      "/Actual Path/Directory/Deeply/Nested/runfile4"
    )
    XCTAssertNil(try? runfiles.rlocation("unknown"))

    XCTAssertEqual(try runfiles.rlocation("/foo").path, "/foo")
  }

  func testManifestBasedRlocationWithRepoMappingFromMain() throws {
    let repoMappingContents = """
    ,config.json,config.json~1.2.3
    ,my_module,_main
    ,my_protobuf,protobuf~3.19.2
    ,my_workspace,_main
    protobuf~3.19.2,config.json,config.json~1.2.3
    protobuf~3.19.2,protobuf,protobuf~3.19.2
    """
    let (repoMapping, cleanRepoMapping) = try createMockFile(name: "_repo_mapping", contents: repoMappingContents)
    defer { try? cleanRepoMapping() }

    let manifestContents = """
    _repo_mapping \(repoMapping.path)
    config.json /etc/config.json
    protobuf~3.19.2/foo/runfile /Actual Path/protobuf/runfile
    _main/bar/runfile /the/path/./to/other//other runfile.txt
    protobuf~3.19.2/bar/dir /Actual Path/Directory
    """
    let (manifest, cleanManifest) = try createMockFile(name: "MANIFEST", contents: manifestContents)
    defer { try? cleanManifest() }

    let runfiles = try Runfiles.create(
      environment: [
        "RUNFILES_MANIFEST_FILE": manifest.path,
        "TEST_SRCDIR": "always ignored",
      ]
    )

    XCTAssertEqual(
      try runfiles.rlocation("my_module/bar/runfile", sourceRepository: "").path,
      "/the/path/./to/other//other runfile.txt"
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_workspace/bar/runfile", sourceRepository: "").path,
      "/the/path/./to/other//other runfile.txt"
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_protobuf/foo/runfile", sourceRepository: "").path,
      "/Actual Path/protobuf/runfile"
    )
    XCTAssertEqual(try runfiles.rlocation("my_protobuf/bar/dir", sourceRepository: "").path, "/Actual Path/Directory")
    XCTAssertEqual(
      try runfiles.rlocation("my_protobuf/bar/dir/file", sourceRepository: "").path,
      "/Actual Path/Directory/file"
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_protobuf/bar/dir/de eply/nes ted/fi~le", sourceRepository: "").path,
      "/Actual Path/Directory/de eply/nes ted/fi~le"
    )

    XCTAssertNil(try? runfiles.rlocation("protobuf/foo/runfile"))
    XCTAssertNil(try? runfiles.rlocation("protobuf/bar/dir"))
    XCTAssertNil(try? runfiles.rlocation("protobuf/bar/dir/file"))
    XCTAssertNil(try? runfiles.rlocation("protobuf/bar/dir/dir/de eply/nes ted/fi~le"))

    XCTAssertEqual(try runfiles.rlocation("_main/bar/runfile").path, "/the/path/./to/other//other runfile.txt")
    XCTAssertEqual(try runfiles.rlocation("protobuf~3.19.2/foo/runfile").path, "/Actual Path/protobuf/runfile")
    XCTAssertEqual(try runfiles.rlocation("protobuf~3.19.2/bar/dir").path, "/Actual Path/Directory")
    XCTAssertEqual(try runfiles.rlocation("protobuf~3.19.2/bar/dir/file").path, "/Actual Path/Directory/file")
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/bar/dir/de eply/nes  ted/fi~le").path,
      "/Actual Path/Directory/de eply/nes  ted/fi~le"
    )

    XCTAssertEqual(try runfiles.rlocation("config.json").path, "/etc/config.json")
    XCTAssertNil(try? runfiles.rlocation("_main"))
    XCTAssertNil(try? runfiles.rlocation("my_module"))
    XCTAssertNil(try? runfiles.rlocation("protobuf"))
  }

  func testManifestBasedRlocationWithRepoMappingFromOtherRepo() throws {
    let repoMappingContents = """
    ,config.json,config.json~1.2.3
    ,my_module,_main
    ,my_protobuf,protobuf~3.19.2
    ,my_workspace,_main
    protobuf~3.19.2,config.json,config.json~1.2.3
    protobuf~3.19.2,protobuf,protobuf~3.19.2
    """

    let (repoMapping, cleanRepoMapping) = try createMockFile(name: "_repo_mapping", contents: repoMappingContents)
    defer { try? cleanRepoMapping() }

    let manifestContents = """
    _repo_mapping \(repoMapping.path)
    config.json /etc/config.json
    protobuf~3.19.2/foo/runfile /Actual Path/protobuf/runfile
    _main/bar/runfile /the/path/./to/other//other runfile.txt
    protobuf~3.19.2/bar/dir /Actual Path/Directory
    """
    let (manifest, cleanManifest) = try createMockFile(name: "mock_manifest", contents: manifestContents)
    defer { try? cleanManifest() }

    let runfiles = try Runfiles.create(
      sourceRepository: "protobuf~3.19.2",
      environment: [
        "RUNFILES_MANIFEST_FILE": manifest.path,
        "TEST_SRCDIR": "always ignored",
      ]
    )

    XCTAssertEqual(try runfiles.rlocation("protobuf/foo/runfile").path, "/Actual Path/protobuf/runfile")
    XCTAssertEqual(try runfiles.rlocation("protobuf/bar/dir").path, "/Actual Path/Directory")
    XCTAssertEqual(try runfiles.rlocation("protobuf/bar/dir/file").path, "/Actual Path/Directory/file")
    XCTAssertEqual(
      try runfiles.rlocation("protobuf/bar/dir/de eply/nes  ted/fi~le").path,
      "/Actual Path/Directory/de eply/nes  ted/fi~le"
    )

    XCTAssertNil(try? runfiles.rlocation("my_module/bar/runfile"))
    XCTAssertNil(try? runfiles.rlocation("my_protobuf/foo/runfile"))
    XCTAssertNil(try? runfiles.rlocation("my_protobuf/bar/dir"))
    XCTAssertNil(try? runfiles.rlocation("my_protobuf/bar/dir/file"))
    XCTAssertNil(try? runfiles.rlocation("my_protobuf/bar/dir/de eply/nes  ted/fi~le"))

    XCTAssertEqual(try runfiles.rlocation("_main/bar/runfile").path, "/the/path/./to/other//other runfile.txt")
    XCTAssertEqual(try runfiles.rlocation("protobuf~3.19.2/foo/runfile").path, "/Actual Path/protobuf/runfile")
    XCTAssertEqual(try runfiles.rlocation("protobuf~3.19.2/bar/dir").path, "/Actual Path/Directory")
    XCTAssertEqual(try runfiles.rlocation("protobuf~3.19.2/bar/dir/file").path, "/Actual Path/Directory/file")
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/bar/dir/de eply/nes  ted/fi~le").path,
      "/Actual Path/Directory/de eply/nes  ted/fi~le"
    )

    XCTAssertEqual(try runfiles.rlocation("config.json").path, "/etc/config.json")
    XCTAssertNil(try? runfiles.rlocation("_main"))
    XCTAssertNil(try? runfiles.rlocation("my_module"))
    XCTAssertNil(try? runfiles.rlocation("protobuf"))
  }

  func testDirectoryBasedRlocation() throws {
    let (runfilesDir, clean) = try createMockDirectory(name: "runfiles_dir")
    defer { try? clean() }

    let runfiles = try Runfiles.create(
      environment: [
        "RUNFILES_DIR": runfilesDir.path,
      ]
    )

    XCTAssertEqual(try runfiles.rlocation("arg").path, runfilesDir.appendingPathComponent("arg").path)
    XCTAssertEqual(try runfiles.rlocation("/foo").path, "/foo")
  }

  func testDirectoryBasedRlocationWithRepoMappingFromMain() throws {
    let repoMappingContents = """
    _,config.json,config.json~1.2.3
    ,my_module,_main
    ,my_protobuf,protobuf~3.19.2
    ,my_workspace,_main
    protobuf~3.19.2,config.json,config.json~1.2.3
    protobuf~3.19.2,protobuf,protobuf~3.19.2
    """
    let (runfilesDir, clean) = try createMockDirectory(name: "runfiles_dir")
    defer { try? clean() }

    let repoMappingFile = runfilesDir.appendingPathComponent("_repo_mapping")
    try repoMappingContents.write(to: repoMappingFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: repoMappingFile) }

    let runfiles = try Runfiles.create(
      environment: [
        "RUNFILES_DIR": runfilesDir.path,
      ]
    )

    XCTAssertEqual(
      try runfiles.rlocation("my_module/bar/runfile").path,
      runfilesDir.appendingPathComponent("_main/bar/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_workspace/bar/runfile").path,
      runfilesDir.appendingPathComponent("_main/bar/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_protobuf/foo/runfile").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/foo/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_protobuf/bar/dir").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_protobuf/bar/dir/file").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir/file").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_protobuf/bar/dir/de eply/nes ted/fi~le").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir/de eply/nes ted/fi~le").path
    )

    XCTAssertEqual(
      try runfiles.rlocation("protobuf/foo/runfile").path,
      runfilesDir.appendingPathComponent("protobuf/foo/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf/bar/dir/dir/de eply/nes ted/fi~le").path,
      runfilesDir.appendingPathComponent("protobuf/bar/dir/dir/de eply/nes ted/fi~le").path
    )

    XCTAssertEqual(
      try runfiles.rlocation("_main/bar/runfile").path,
      runfilesDir.appendingPathComponent("_main/bar/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/foo/runfile").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/foo/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/bar/dir").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/bar/dir/file").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir/file").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/bar/dir/de eply/nes  ted/fi~le").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir/de eply/nes  ted/fi~le").path
    )

    XCTAssertEqual(try runfiles.rlocation("config.json").path, runfilesDir.appendingPathComponent("config.json").path)
  }

  func testDirectoryBasedRlocationWithRepoMappingFromOtherRepo() throws {
    let repoMappingContents = """
    _,config.json,config.json~1.2.3
    ,my_module,_main
    ,my_protobuf,protobuf~3.19.2
    ,my_workspace,_main
    protobuf~3.19.2,config.json,config.json~1.2.3
    protobuf~3.19.2,protobuf,protobuf~3.19.2
    """
    let (runfilesDir, clean) = try createMockDirectory(name: "runfiles_dir")
    defer { try? clean() }

    let repoMappingFile = runfilesDir.appendingPathComponent("_repo_mapping")
    try repoMappingContents.write(to: repoMappingFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: repoMappingFile) }

    let runfiles = try Runfiles.create(
      sourceRepository: "protobuf~3.19.2",
      environment: [
        "RUNFILES_DIR": runfilesDir.path,
      ]
    )

    XCTAssertEqual(
      try runfiles.rlocation("protobuf/foo/runfile").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/foo/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf/bar/dir").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf/bar/dir/file").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir/file").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf/bar/dir/de eply/nes  ted/fi~le").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir/de eply/nes  ted/fi~le").path
    )

    XCTAssertEqual(
      try runfiles.rlocation("my_module/bar/runfile").path,
      runfilesDir.appendingPathComponent("my_module/bar/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("my_protobuf/bar/dir/de eply/nes  ted/fi~le").path,
      runfilesDir.appendingPathComponent("my_protobuf/bar/dir/de eply/nes  ted/fi~le").path
    )

    XCTAssertEqual(
      try runfiles.rlocation("_main/bar/runfile").path,
      runfilesDir.appendingPathComponent("_main/bar/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/foo/runfile").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/foo/runfile").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/bar/dir").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/bar/dir/file").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir/file").path
    )
    XCTAssertEqual(
      try runfiles.rlocation("protobuf~3.19.2/bar/dir/de eply/nes  ted/fi~le").path,
      runfilesDir.appendingPathComponent("protobuf~3.19.2/bar/dir/de eply/nes  ted/fi~le").path
    )

    XCTAssertEqual(try runfiles.rlocation("config.json").path, runfilesDir.appendingPathComponent("config.json").path)
  }

  func testComputeRunfilesPath_withValidManifestFile() throws {
      let mockManifestFile = "/path/to/manifest"
      let isRunfilesManifest: (String) -> Bool = { $0 == mockManifestFile }
      let isRunfilesDirectory: (String) -> Bool = { _ in false }

      let path = try computeRunfilesPath(
          argv0: "/path/to/argv0",
          manifestFile: mockManifestFile,
          runfilesDir: nil,
          isRunfilesManifest: isRunfilesManifest,
          isRunfilesDirectory: isRunfilesDirectory
      )
      XCTAssertEqual(path, RunfilesPath.manifest(mockManifestFile))
  }

  func testComputeRunfilesPath_withValidRunfilesDirectory() throws {
      let mockRunfilesDir = "/path/to/runfiles"
      let isRunfilesManifest: (String) -> Bool = { _ in false }
      let isRunfilesDirectory: (String) -> Bool = { $0 == mockRunfilesDir }

      let path = try computeRunfilesPath(
          argv0: "/path/to/argv0",
          manifestFile: nil,
          runfilesDir: mockRunfilesDir,
          isRunfilesManifest: isRunfilesManifest,
          isRunfilesDirectory: isRunfilesDirectory
      )

      XCTAssertEqual(path, RunfilesPath.directory(mockRunfilesDir))
  }

  func testComputeRunfilesPath_withInvalidManifestAndDirectory() {
      let isRunfilesManifest: (String) -> Bool = { _ in false }
      let isRunfilesDirectory: (String) -> Bool = { _ in false }

      XCTAssertThrowsError(try computeRunfilesPath(
          argv0: "/path/to/argv0",
          manifestFile: "/invalid/manifest",
          runfilesDir: "/invalid/runfiles",
          isRunfilesManifest: isRunfilesManifest,
          isRunfilesDirectory: isRunfilesDirectory
      ))
  }

  func testComputeRunfilesPath_withWellKnownManifestFile() throws {
      let argv0 = "/path/to/argv0"
      let isRunfilesManifest: (String) -> Bool = { $0 == "/path/to/argv0.runfiles/MANIFEST" }
      let isRunfilesDirectory: (String) -> Bool = { _ in false }

      let path = try computeRunfilesPath(
          argv0: argv0,
          manifestFile: nil,
          runfilesDir: nil,
          isRunfilesManifest: isRunfilesManifest,
          isRunfilesDirectory: isRunfilesDirectory
      )

      XCTAssertEqual(path, RunfilesPath.manifest("/path/to/argv0.runfiles/MANIFEST"))
  }

  func testComputeRunfilesPath_withWellKnownRunfilesDir() throws {
      let argv0 = "/path/to/argv0"
      let isRunfilesManifest: (String) -> Bool = { _ in false }
      let isRunfilesDirectory: (String) -> Bool = { $0 == "/path/to/argv0.runfiles" }

      let path = try computeRunfilesPath(
          argv0: argv0,
          manifestFile: nil,
          runfilesDir: nil,
          isRunfilesManifest: isRunfilesManifest,
          isRunfilesDirectory: isRunfilesDirectory
      )

      XCTAssertEqual(path, RunfilesPath.directory("/path/to/argv0.runfiles"))
  }

  func testComputeRunfilesPath_missingRunfilesLocations() {
      let argv0 = "/path/to/argv0"
      let isRunfilesManifest: (String) -> Bool = { _ in false }
      let isRunfilesDirectory: (String) -> Bool = { _ in false }

      XCTAssertThrowsError(try computeRunfilesPath(
          argv0: argv0,
          manifestFile: nil,
          runfilesDir: nil,
          isRunfilesManifest: isRunfilesManifest,
          isRunfilesDirectory: isRunfilesDirectory
      ))
  }

  func testDirectoryBasedRlocationWithRepoMapping_FromExtensionRepo() throws {
    let repoMappingContents = """
    _,config.json,config.json+1.2.3
    ,my_module,_main
    ,my_protobuf,protobuf+3.19.2
    ,my_workspace,_main
    my_module++ext+*,my_module,my_module+
    my_module++ext+*,repo1,my_module++ext+repo1
    """
    let (runfilesDir, clean) = try createMockDirectory(name: "foo.runfiles")
    defer { try? clean() }

    let repoMappingFile = runfilesDir.appendingPathComponent("_repo_mapping")
    try repoMappingContents.write(to: repoMappingFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: repoMappingFile) }

    let runfiles = try Runfiles.create(
        sourceRepository: "my_module++ext+repo1",
        environment: [
            "RUNFILES_DIR": runfilesDir.path,
        ]
    )

    XCTAssertEqual(
        try runfiles.rlocation("my_module/foo").path,
        runfilesDir.appendingPathComponent("my_module+/foo").path
    )
    XCTAssertEqual(
        try runfiles.rlocation("repo1/foo").path,
        runfilesDir.appendingPathComponent("my_module++ext+repo1/foo").path
    )
    XCTAssertEqual(
        try runfiles.rlocation("repo2+/foo").path,
        runfilesDir.appendingPathComponent("repo2+/foo").path
    )
  }
}

enum RunfilesTestError: Error {
  case missingTestTmpDir
}

func createMockFile(name: String, contents: String) throws -> (URL, () throws -> Void) {

  guard let tmpBaseDirectory = ProcessInfo.processInfo.environment["TEST_TMPDIR"] else {
    XCTFail()
    throw RunfilesTestError.missingTestTmpDir
  }

  let fallbackTempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
  let tempDirectory = URL(fileURLWithPath: tmpBaseDirectory).appendingPathComponent(fallbackTempDirectory.lastPathComponent)
  let tempFile = tempDirectory.appendingPathComponent(name)

  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  try contents.write(to: tempFile, atomically: true, encoding: .utf8)

  return (tempFile, {
    try FileManager.default.removeItem(at: tempFile)
    try FileManager.default.removeItem(at: tempDirectory)
  })
}

func createMockDirectory(name _: String) throws -> (URL, () throws -> Void) {
  guard let tmpBaseDirectory = ProcessInfo.processInfo.environment["TEST_TMPDIR"] else {
    XCTFail()
    throw RunfilesTestError.missingTestTmpDir
  }

  let fallbackTempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
  let tempDirectory = URL(fileURLWithPath: tmpBaseDirectory).appendingPathComponent(fallbackTempDirectory.lastPathComponent)

  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

  return (tempDirectory, {
    try FileManager.default.removeItem(at: tempDirectory)
  })
}

// case_links.swift: a Windows SDK and MSVC tree (a "winsysroot": VC/Tools/MSVC/
// <version> and Windows Kits/10) made usable from a case-sensitive file
// system. Windows' headers include each other, and Swift's module maps name
// them, in casings other than the files' own (<WinSock2.h> for winsock2.h);
// for every name used that exists only in another case, a symbolic link of
// that name is made beside the file, as xwin's splat does. Run by
// make_msvc_sysroot.sh.
//
//   swift case_links.swift <winsysroot> [<more include directories: Swift's module maps' folder>…]
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard let root = arguments.first else {
    FileHandle.standardError.write(Data("usage: case_links.swift <winsysroot> [<directory>…]\n".utf8))
    exit(2)
}
let manager = FileManager.default

/// Every include directory: MSVC's include and each Windows Kits Include/<v>/<area>.
var includeDirectories: [String] = []
for msvc in (try? manager.contentsOfDirectory(atPath: "\(root)/VC/Tools/MSVC")) ?? [] {
    includeDirectories.append("\(root)/VC/Tools/MSVC/\(msvc)/include")
}
for version in (try? manager.contentsOfDirectory(atPath: "\(root)/Windows Kits/10/Include")) ?? [] {
    for area in ["ucrt", "um", "shared", "winrt"] {
        includeDirectories.append("\(root)/Windows Kits/10/Include/\(version)/\(area)")
    }
}
/// The library folders, whose names linkers are given in their own casings too.
var libraryDirectories: [String] = []
for msvc in (try? manager.contentsOfDirectory(atPath: "\(root)/VC/Tools/MSVC")) ?? [] {
    for arch in ["arm64", "x64"] { libraryDirectories.append("\(root)/VC/Tools/MSVC/\(msvc)/lib/\(arch)") }
}
for version in (try? manager.contentsOfDirectory(atPath: "\(root)/Windows Kits/10/Lib")) ?? [] {
    for area in ["ucrt", "um"] {
        for arch in ["arm64", "x64"] { libraryDirectories.append("\(root)/Windows Kits/10/Lib/\(version)/\(area)/\(arch)") }
    }
}

/// Lowercased relative path → the file's own relative path, per directory.
func index(_ directory: String) -> [String: String] {
    var found: [String: String] = [:]
    guard let walker = manager.enumerator(atPath: directory) else { return found }
    while let path = walker.nextObject() as? String {
        found[path.lowercased()] = path
    }
    return found
}

let includeIndexes = includeDirectories.map { ($0, index($0)) }
var made = 0

/// A link at `name` (relative to one of the directories) to the file that
/// exists there in another case, unless a file of that very name exists.
func link(_ name: String, in indexes: [(String, [String: String])]) {
    let name = name.replacingOccurrences(of: "\\", with: "/")
    for (directory, _) in indexes {
        if manager.fileExists(atPath: "\(directory)/\(name)") { return }
    }
    for (directory, entries) in indexes {
        guard let real = entries[name.lowercased()] else { continue }
        let at = "\(directory)/\(name)"
        try? manager.createDirectory(atPath: (at as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // Relative, so the tree can move.
        let depth = name.split(separator: "/").count - 1
        let target = String(repeating: "../", count: depth) + real
        if (try? manager.createSymbolicLink(atPath: at, withDestinationPath: target)) != nil { made += 1 }
        return
    }
}

let includePattern = try! NSRegularExpression(pattern: #"^\s*#\s*include\s*[<"]([^>"]+)[>"]"#, options: [.anchorsMatchLines])
let headerPattern = try! NSRegularExpression(pattern: #"header\s+"([^"]+)""#)

func names(in file: String, _ pattern: NSRegularExpression) -> [String] {
    guard let data = manager.contents(atPath: file) else { return [] }
    let text = String(decoding: data, as: UTF8.self)
    let range = NSRange(text.startIndex..., in: text)
    return pattern.matches(in: text, range: range).compactMap { match in
        Range(match.range(at: 1), in: text).map { String(text[$0]) }
    }
}

var referenced = Set<String>()
for (directory, entries) in includeIndexes {
    for path in entries.values where !path.hasSuffix("/") {
        referenced.formUnion(names(in: "\(directory)/\(path)", includePattern))
    }
}
for extra in arguments.dropFirst() {
    for file in (try? manager.contentsOfDirectory(atPath: extra)) ?? [] where file.hasSuffix(".modulemap") {
        referenced.formUnion(names(in: "\(extra)/\(file)", headerPattern))
    }
}
for name in referenced.sorted() { link(name, in: includeIndexes) }
// And every header by its lowercased name, which code written for Windows
// often uses (<dbghelp.h> for DbgHelp.h).
for (directory, entries) in includeIndexes {
    for path in entries.values where path.lowercased() != path {
        let lowered = path.lowercased()
        let at = "\(directory)/\(lowered)"
        guard !manager.fileExists(atPath: at) else { continue }
        try? manager.createDirectory(atPath: (at as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let depth = lowered.split(separator: "/").count - 1
        if (try? manager.createSymbolicLink(atPath: at, withDestinationPath: String(repeating: "../", count: depth) + path)) != nil { made += 1 }
    }
}

// Libraries: the names Swift's module maps `link` and the headers'
// `#pragma comment(lib, …)` ask for, each linked to the library of that
// name in another case (lld-link searches case-insensitively only on
// Windows); and every library's lowercased name too.
let libraryIndexes = libraryDirectories.map { ($0, index($0)) }
let linkPattern = try! NSRegularExpression(pattern: #"\blink\s+"([^"]+)""#)
let pragmaPattern = try! NSRegularExpression(pattern: #"#\s*pragma\s+comment\s*\(\s*lib\s*,\s*"([^"]+)""#)
var libraries = Set<String>()
for (directory, entries) in includeIndexes {
    for path in entries.values { libraries.formUnion(names(in: "\(directory)/\(path)", pragmaPattern)) }
}
for extra in arguments.dropFirst() {
    for file in (try? manager.contentsOfDirectory(atPath: extra)) ?? [] where file.hasSuffix(".modulemap") {
        libraries.formUnion(names(in: "\(extra)/\(file)", linkPattern))
    }
}
for (directory, entries) in libraryIndexes {
    for file in entries.values where file.lowercased() != file && !manager.fileExists(atPath: "\(directory)/\(file.lowercased())") {
        if (try? manager.createSymbolicLink(atPath: "\(directory)/\(file.lowercased())", withDestinationPath: file)) != nil { made += 1 }
    }
}
for name in libraries.sorted() {
    let file = name.lowercased().hasSuffix(".lib") ? name : name + ".lib"
    link(file, in: libraryIndexes)
}
print("case_links: \(made) links, \(referenced.count) names referenced")

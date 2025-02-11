import BazelRunfiles

do {
    let runfiles = try Runfiles.create()
    // Runfiles lookup paths have the form `my_workspace/package/file`.
    // Runfiles path lookup may throw.
    let fileURL = try runfiles.rlocation("build_bazel_rules_swift/examples/runfiles/data/sample.txt")
    print("file: \(fileURL)")

    // Runfiles path lookup may return a non-existent path.
    let content = try String(contentsOf: fileURL, encoding: .utf8)

    assert(content == "Hello runfiles")
    print(content)
} catch {
     print("runfiles error: \(error)")
}

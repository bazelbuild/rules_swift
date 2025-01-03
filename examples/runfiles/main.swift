import BazelRunfiles

let runfiles = try Runfiles.create()

// Runfiles lookup paths have the form `my_workspace/package/file`.
// Runfiles path lookup may return nil.
guard let runFile = runfiles.rlocation("build_bazel_rules_swift/examples/runfiles/data/sample.txt") else {
    fatalError("couldn't resolve runfile")
}

print(runFile)

// Runfiles path lookup may return a non-existent path.
let content = try String(contentsOf: runFile, encoding: .utf8)

assert(content == "Hello runfiles")
print(content)

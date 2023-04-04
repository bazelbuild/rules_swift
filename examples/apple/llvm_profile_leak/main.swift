import Foundation

let process: Process = .init()
process.launchPath = "/usr/bin/env"
process.currentDirectoryPath = "/Users/maxwellelliott/Development/rules_swift"
process.arguments = [
    "bazel",
    "coverage",
    "//examples/apple/llvm_profile_leak/...",
    "--experimental_use_llvm_covmap",
    "--action_env=LCOV_MERGER=/usr/bin/true",
    "--spawn_strategy=worker,sandboxed,local",
    "--experimental_inprocess_symlink_creation",
    "--define=apple.experimental.tree_artifact_outputs=1",
    "--incompatible_strict_action_env"
]
let outputPipe: Pipe = .init()
let errorPipe: Pipe = .init()
process.standardOutput = outputPipe
process.standardError = errorPipe
process.launch()
process.waitUntilExit()

let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
let output = String(decoding: outputData, as: UTF8.self)
let error = String(decoding: errorData, as: UTF8.self)
print("output: \(output)")
print("error: \(error)")

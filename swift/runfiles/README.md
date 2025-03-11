# Swift BazelRunfiles library

This is a Bazel Runfiles lookup library for Bazel-built Swift binaries and tests.

Learn about runfiles: read [Runfiles guide](https://bazel.build/extending/rules#runfiles)
or watch [Fabian's BazelCon talk](https://www.youtube.com/watch?v=5NbgUMH1OGo).

## Usage

1.  Depend on this runfiles library from your build rule:

```python
swift_binary(
    name = "my_binary",
    ...
    data = ["//path/to/my/data.txt"],
    deps = ["@build_bazel_rules_swift//swift/runfiles"],
)
```

2.  Include the runfiles library:

```swift
import BazelRunfiles
```

3.  Create a Runfiles instance and use `rlocation` to look up runfile urls:

```swift
import BazelRunfiles

do {
    let runfiles = try Runfiles.create()
    let fileURL = try runfiles.rlocation("my_workspace/path/to/my/data.txt")
    print("file: \(fileURL)")
} catch {
     print("runfiles error: \(error)")
}
```

The code above:

- Creates a manifest- or directory-based implementation based on
  the environment variables in `Process.processInfo.environment`.
  See `Runfiles.create()` for more info.
- The `Runfiles.create` function uses the runfiles manifest and the runfiles
  directory from the `RUNFILES_MANIFEST_FILE` and `RUNFILES_DIR` environment
  variables. If not present, the function looks for the manifest and directory
  near `CommandLine.arguments.first` (e.g. `argv[0]` the path of the main program).

If you want to start subprocesses, the runfiles library helps you set the required environment variables for them to find their runfiles:

```swift
import BazelRunfiles
import Foundation

do {

    let runfiles = try Runfiles.create()
    let executableURL = try runfiles.rlocation("my_workspace/path/to/binary")

    let process = Process()
    process.executableURL = executableURL
    process.environment = runfiles.envVars()

    do {
        // Launch the process
        try process.run()
        process.waitUntilExit()
    } catch {
        // ...
    }
} catch {
    fatalError("runfiles error: \(error)")
}
```

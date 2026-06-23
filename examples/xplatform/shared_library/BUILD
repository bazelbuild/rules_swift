load("//swift:swift_binary.bzl", "swift_binary")

licenses(["notice"])

# `linkshared` links a native dynamic library instead of an executable: a
# `.dylib` on Apple platforms, a `.so` on Linux/Android, and a `.dll` (plus an
# import `.lib`) on Windows.
swift_binary(
    name = "shared_library",
    srcs = ["greeting.swift"],
    linkshared = True,
)

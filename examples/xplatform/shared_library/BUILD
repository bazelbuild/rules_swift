load("//swift:swift_binary.bzl", "swift_binary")

licenses(["notice"])

# `linkshared` links a native dynamic library instead of an executable: a
# `.dylib` on Apple platforms or a `.so` on Linux.
swift_binary(
    name = "shared_library",
    srcs = ["greeting.swift"],
    linkshared = True,
)

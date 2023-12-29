"""Bazel rules to define Swift proto libraries and compilers."""

load(
    "//swift:swift.bzl",
    _swift_proto_compiler = "swift_proto_compiler",
    _swift_proto_library = "new_swift_proto_library",
)

swift_proto_compiler = _swift_proto_compiler
swift_proto_library = _swift_proto_library

load("//swift:swift.bzl", "swift_binary", "swift_library", "swift_import")

swift_binary(
    name = "hello_world",
    deps = [":main"],
)

swift_library(
    name = "main",
    srcs = ["main.swift"],
    deps = [
        ":import"
    ]
)

genrule(
    name = "generate_archive",
    cmd = "dd if=/dev/zero of=$@ bs=200 count=24 status=none",
    outs = ["archive.a"]
)

genrule(
    name = "generate_swiftmodule",
    cmd = "dd if=/dev/zero of=$@ bs=200 count=24 status=none",
    outs = ["archive.swiftmodule"]
)

swift_import(
    name = "import",
    module_name = "SwiftImport",
    archives = [":generate_archive"],
    swiftmodule = ":generate_swiftmodule",
)

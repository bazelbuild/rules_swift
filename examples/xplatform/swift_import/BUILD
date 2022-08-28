load("//swift:swift.bzl", "swift_binary", "swift_import", "swift_library")

swift_binary(
    name = "hello_world",
    deps = [":main"],
)

swift_library(
    name = "main",
    srcs = ["main.swift"],
    deps = [
        ":import",
    ],
)

genrule(
    name = "generate_archive",
    outs = ["archive.a"],
    cmd = "mkfile 500 $@",
)

genrule(
    name = "generate_swiftmodule",
    outs = ["archive.swiftmodule"],
    cmd = "mkfile 500 $@",
)

swift_import(
    name = "import",
    archives = [":generate_archive"],
    module_name = "SwiftImport",
    swiftmodule = ":generate_swiftmodule",
)

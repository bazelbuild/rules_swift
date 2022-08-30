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
    name = "generate_swiftmodule",
    outs = ["archive.swiftmodule"],
    cmd = "for i in {1..100};do echo \"string\" >> $@;done",
)

swift_import(
    name = "import",
    archives = ["import.a"],
    module_name = "SwiftImport",
    swiftmodule = ":generate_swiftmodule",
)

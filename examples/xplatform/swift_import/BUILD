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
    cmd = "for i in {1..1000};do echo \"string\" >> $@;done",
)

genrule(
    name = "generate_swiftmodule",
    outs = ["archive.swiftmodule"],
    cmd = "for i in {1..1000};do echo \"string\" >> $@;done",
)

swift_import(
    name = "import",
    archives = [":generate_archive"],
    module_name = "SwiftImport",
    swiftmodule = ":generate_swiftmodule",
)

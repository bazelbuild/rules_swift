load("//swift:swift.bzl", "swift_binary", "swift_import", "swift_library")
load(":get_swiftmodule.bzl", "get_swiftmodule")

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

swift_import(
    name = "import",
    archives = ["libdep.a"],
    module_name = "dep",
    swiftmodule = ":foo",
)

get_swiftmodule(
    name = "foo",
    lib = "dep",
)

swift_library(
    name = "dep",
    srcs = ["dep.swift"],
    module_name = "dep",
)

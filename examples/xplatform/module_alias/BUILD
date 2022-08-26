load("//swift:swift.bzl", "swift_binary", "swift_library", "swift_module_alias")

swift_binary(
    name = "hello_world",
    deps = [":main_alias"],
)

swift_library(
    name = "main",
    srcs = ["main.swift"],
)

swift_module_alias(
    name = "main_alias",
    module_name = "Main_Alias",
    deps = [":main"],
)

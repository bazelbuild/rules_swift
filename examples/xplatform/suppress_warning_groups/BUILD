load("//swift:swift_library.bzl", "swift_library")

swift_library(
    name = "impl_dep",
    srcs = ["ImplDep.swift"],
    module_name = "ImplDep",
)

swift_library(
    name = "impl_only_suppressed",
    srcs = ["ImplementationOnlySuppressed.swift"],
    private_deps = [":impl_dep"],
    suppress_warning_groups = ["ImplementationOnlyDeprecated"],
)

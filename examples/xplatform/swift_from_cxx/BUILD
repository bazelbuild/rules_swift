load("//swift:swift_library.bzl", "swift_library")

swift_library(
    name = "landscape",
    srcs = ["Landscape.swift"],
    copts = ["-cxx-interoperability-mode=default"],
    # Auto-generates landscape-Swift.h.
    # It can be customized with generated_header_name.
    generates_header = True,
    module_name = "SwiftLandscape",
)

cc_binary(
    name = "landscape_cxx_client",
    srcs = ["landscape_cxx_client.cpp"],
    deps = [":landscape"],
)

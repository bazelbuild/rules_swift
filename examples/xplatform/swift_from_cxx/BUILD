load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")

swift_library(
    name = "landscape",
    srcs = ["Landscape.swift"],
    features = ["swift.enable_cpp20_interop"],
    generates_header = True,
    module_name = "SwiftLandscape",
)

cc_library(
    name = "landscape_cxx",
    srcs = ["landscape_cxx_client.cpp"],
    deps = [":landscape"],
)

swift_binary(
    name = "landscape_cxx_bin",
    deps = [":landscape_cxx"],
)

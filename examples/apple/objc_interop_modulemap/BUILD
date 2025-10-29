# This example tests that Swift code can be called from Objective-C code and
# vice versa when it is linked into the existing native linking rules for Apple
# platforms.

load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")

licenses(["notice"])

swift_interop_hint(
    name = "PrintStream_swift_interop",
    module_name = "examples_apple_objc_interop_modulemap_PrintStream",
    system_pcms = select({
        # this lets objc library to depend on the same system_sdks as the swift library
        "//conditions:default": [
            "@build_bazel_rules_swift//system_sdks:system_sdks",
        ],
    }),
)

objc_library(
    name = "PrintStream",
    srcs = ["OIPrintStream.m"],
    hdrs = ["OIPrintStream.h"],
    aspect_hints = [":PrintStream_swift_interop"],
    target_compatible_with = ["@platforms//os:macos"],
)

swift_library(
    name = "Printer",
    srcs = ["Printer.swift"],
    features = ["swift.propagate_generated_module_map"],
    generated_header_name = "generated_header/Printer-Swift.h",
    generates_header = True,
    deps = [":PrintStream"],
)

objc_library(
    name = "main",
    srcs = ["main.m"],
    enable_modules = True,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":Printer"],
)

swift_binary(
    name = "objc_interop_modulemap",
    deps = [":main"],
)

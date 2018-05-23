# This example tests that Swift code can be called from Objective-C code and
# vice versa when it is linked into the existing native linking rules for Apple
# platforms.

licenses(["notice"])

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

objc_library(
    name = "PrintStream",
    srcs = ["OIPrintStream.m"],
    hdrs = ["OIPrintStream.h"],
)

swift_library(
    name = "Printer",
    srcs = ["Printer.swift"],
    deps = [":PrintStream"],
)

objc_library(
    name = "main",
    srcs = ["main.m"],
    deps = [":Printer"],
)

apple_binary(
    name = "objc_interop",
    platform_type = "macos",
    deps = [":main"],
)

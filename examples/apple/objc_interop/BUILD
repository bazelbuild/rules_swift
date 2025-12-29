# This example tests that Swift code can be called from Objective-C code and
# vice versa when it is linked into the existing native linking rules for Apple
# platforms.

load("@rules_cc//cc:objc_library.bzl", "objc_library")
load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)

licenses(["notice"])

objc_library(
    name = "PrintStream",
    srcs = ["OIPrintStream.m"],
    hdrs = ["OIPrintStream.h"],
)

swift_library(
    name = "Printer",
    srcs = ["Printer.swift"],
    generates_header = True,
    deps = [
        ":PrintStream",
    ],
)

objc_library(
    name = "main",
    srcs = ["main.m"],
    deps = [":Printer"],
)

swift_binary(
    name = "objc_interop",
    deps = [":main"],
)

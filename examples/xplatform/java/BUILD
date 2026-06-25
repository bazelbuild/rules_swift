load("@rules_java//java:defs.bzl", "java_library", "java_test")
load("//swift:swift_binary.bzl", "swift_binary")

licenses(["notice"])

swift_binary(
    name = "SwiftJNI",
    srcs = ["SwiftJNI.swift"],
    linkshared = True,
)

java_library(
    name = "swift_value",
    srcs = ["SwiftValue.java"],
)

java_test(
    name = "SwiftValueTest",
    srcs = ["SwiftValueTest.java"],
    args = ["$(rootpath :SwiftJNI)"],
    data = [":SwiftJNI"],
    main_class = "com.example.swiftjni.SwiftValueTest",
    use_testrunner = False,
    deps = [":swift_value"],
)

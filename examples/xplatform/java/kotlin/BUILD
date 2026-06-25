load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_test")
load("//swift:swift_binary.bzl", "swift_binary")

licenses(["notice"])

swift_binary(
    name = "SwiftKotlinJNI",
    srcs = ["SwiftKotlinJNI.swift"],
    linkshared = True,
)

kt_jvm_test(
    name = "SwiftValueKotlinTest",
    srcs = ["SwiftValueKotlinTest.kt"],
    args = ["$(rootpath :SwiftKotlinJNI)"],
    data = [":SwiftKotlinJNI"],
    main_class = "com.example.swiftjni.kotlin.SwiftValueKotlinTestKt",
)

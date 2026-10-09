load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

# A checked-in directory, including a nested directory.
swift_library(
    name = "source_directory",
    module_name = "SourceDirectory",
    srcs_dirs = ["Sources"],
    tags = FIXTURE_TAGS,
)

# A binary whose only source is a checked-in directory containing `main.swift`.
swift_binary(
    name = "source_directory_binary",
    srcs_dirs = ["Main"],
    tags = FIXTURE_TAGS,
    deps = [":source_directory"],
)

genrule(
    name = "generated_file",
    outs = ["Generated.swift"],
    cmd = "echo 'let generated = 1' > $@",
    tags = FIXTURE_TAGS,
)

# A generated file isn't a directory.
swift_library(
    name = "file_in_srcs_dirs",
    srcs_dirs = [":generated_file"],
    tags = FIXTURE_TAGS,
)

sh_test(
    name = "source_directory_test",
    srcs = ["source_directory_test.sh"],
    args = ["$(rootpath :source_directory_binary)"],
    data = [":source_directory_binary"],
)

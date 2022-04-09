load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")

def bzl_test(name, bzl_file, bzl_target, symbol):
    bzl_gen_file_name = name + "_bzl_file"
    write_file(
        name = bzl_gen_file_name,
        out = name + "_generated.bzl",
        content = [
            "load(\"{bzl_file}\", \"{symbol}\")".format(
                bzl_file = bzl_file,
                symbol = symbol,
            ),
            "",
            "def macro_with_doc(name):",
            "    \"\"\"This macro does nothing.",
            "",
            "    Args:",
            "        name: A `string` value.",
            "    \"\"\"",
            "    return {symbol}".format(
                symbol = symbol,
            ),
        ],
    )

    bzl_gen_lib_name = name + "_bzl_lib"
    bzl_library(
        name = bzl_gen_lib_name,
        srcs = [bzl_gen_file_name],
        deps = [bzl_target],
    )

    stardoc_name = name + "_stardoc"
    stardoc(
        name = stardoc_name,
        out = stardoc_name + ".md_",
        input = bzl_gen_file_name,
        deps = [bzl_gen_lib_name],
    )

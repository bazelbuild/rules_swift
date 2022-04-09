load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")

# def bzl_test(name, bzl_file, bzl_target, symbol):
def bzl_test(name, src, deps):
    """Provides build-time assurances that `bzl_library` declarations exist and are referenced properly.

    Args:
        name:

    Returns:
    """
    # macro_name = name + "_macro"
    # macro_filename = macro_name + ".bzl"
    # write_file(
    #     name = macro_name,
    #     out = macro_filename,
    #     content = [
    #         "load(\"{bzl_file}\", \"{symbol}\")".format(
    #             bzl_file = bzl_file,
    #             symbol = symbol,
    #         ),
    #         "",
    #         "def macro_with_doc(name):",
    #         "    \"\"\"This macro does nothing.",
    #         "",
    #         "    Args:",
    #         "        name: A `string` value.",
    #         "    \"\"\"",
    #         "    return {symbol}".format(
    #             symbol = symbol,
    #         ),
    #     ],
    # )

    macro_lib_name = name + "_macro_lib"
    bzl_library(
        name = macro_lib_name,
        srcs = [src],
        deps = deps,
    )

    stardoc(
        name = name,
        out = macro_lib_name + ".md_",
        input = src,
        deps = [macro_lib_name],
    )

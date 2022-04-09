load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")

def bzl_test(name, bzl_file, bzl_target, symbol):
    """Provides build-time assurances that `bzl_library` declarations exist and are referenced properly.

    Args:
        name:

    Returns:
    """
    macro_name = name + "_macro"
    macro_filename = macro_name + ".bzl"
    write_file(
        name = macro_name,
        out = macro_filename,
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

    macro_lib_name = macro_name + "_lib"
    bzl_library(
        name = macro_lib_name,
        # srcs = [macro_name],
        srcs = [macro_filename],
        deps = [bzl_target],
    )

    # DEBUG BEGIN
    print("*** CHUCK macro_filename: ", macro_filename)

    # DEBUG END
    stardoc(
        name = name,
        out = macro_lib_name + ".md_",
        input = macro_filename,
        # input = ":" + macro_filename,
        deps = [macro_lib_name],
    )

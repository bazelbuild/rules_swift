"""Tests for `utils` module."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//swift/internal:utils.bzl", "include_dev_srch_paths")

def _include_dev_srch_paths_test(ctx):
    env = unittest.begin(ctx)

    tests = [
        struct(
            msg = """\
testonly is false, always_include_developer_search_paths does not exist\
""",
            attr = struct(testonly = False),
            exp = False,
        ),
        struct(
            msg = """\
testonly is true, always_include_developer_search_paths does not exist\
""",
            attr = struct(testonly = True),
            exp = True,
        ),
        struct(
            msg = """\
testonly is false, always_include_developer_search_paths is false\
""",
            attr = struct(
                testonly = False,
                always_include_developer_search_paths = False,
            ),
            exp = False,
        ),
        struct(
            msg = """\
testonly is false, always_include_developer_search_paths is true\
""",
            attr = struct(
                testonly = False,
                always_include_developer_search_paths = True,
            ),
            exp = True,
        ),
        struct(
            msg = """\
testonly is true, always_include_developer_search_paths is false\
""",
            attr = struct(
                testonly = True,
                always_include_developer_search_paths = False,
            ),
            exp = True,
        ),
        struct(
            msg = """\
testonly is true, always_include_developer_search_paths is true\
""",
            attr = struct(
                testonly = True,
                always_include_developer_search_paths = True,
            ),
            exp = True,
        ),
    ]
    for t in tests:
        ctx = struct(attr = t.attr)
        actual = include_dev_srch_paths(ctx)
        asserts.equals(env, t.exp, actual, t.msg)

    return unittest.end(env)

include_dev_srch_paths_test = unittest.make(_include_dev_srch_paths_test)

def utils_test_suite(name):
    return unittest.suite(
        name,
        include_dev_srch_paths_test,
    )

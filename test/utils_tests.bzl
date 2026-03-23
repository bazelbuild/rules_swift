"""Tests for `utils` module."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//swift/internal:extensions/standalone_toolchain.bzl", "get_download_url")

# buildifier: disable=bzl-visibility
load("//swift/internal:utils.bzl", "include_developer_search_paths")

def _include_developer_search_paths_test(ctx):
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
        actual = include_developer_search_paths(ctx.attr)
        asserts.equals(env, t.exp, actual, t.msg)

    return unittest.end(env)

include_developer_search_paths_test = unittest.make(_include_developer_search_paths_test)

def _standalone_toolchain_download_url_test(ctx):
    env = unittest.begin(ctx)

    # The validity of these URLs can be tested by running (for instance):
    # bazel run //tools/swift-releases -- list 6.2.1 --platform ubuntu22.04 --dry-run
    tests = [
        # A released toolchain
        struct(
            version = "6.2.1",
            platform = "ubuntu22.04",
            expected = "https://download.swift.org/swift-6.2.1-release/ubuntu2204/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE-ubuntu22.04.tar.gz",
        ),
        # A branch snapshot toolchain
        struct(
            version = "6.3-snapshot-2026-03-05",
            platform = "ubuntu22.04",
            expected = "https://download.swift.org/swift-6.3-branch/ubuntu2204/swift-6.3-DEVELOPMENT-SNAPSHOT-2026-03-05-a/swift-6.3-DEVELOPMENT-SNAPSHOT-2026-03-05-a-ubuntu22.04.tar.gz",
        ),
        # A mainline snapshot toolchain
        struct(
            version = "main-snapshot-2026-03-16",
            platform = "ubuntu22.04",
            expected = "https://download.swift.org/development/ubuntu2204/swift-DEVELOPMENT-SNAPSHOT-2026-03-16-a/swift-DEVELOPMENT-SNAPSHOT-2026-03-16-a-ubuntu22.04.tar.gz",
        ),
        # An aarch64 Linux toolchain
        struct(
            version = "6.2.1",
            platform = "ubuntu22.04-aarch64",
            expected = "https://download.swift.org/swift-6.2.1-release/ubuntu2204-aarch64/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE-ubuntu22.04-aarch64.tar.gz",
        ),
        # A MacOS standalone toolchain (also called in the API an Xcode toolchain)
        struct(
            version = "6.2.1",
            platform = "xcode",
            expected = "https://download.swift.org/swift-6.2.1-release/xcode/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE-osx.pkg",
        ),
    ]
    for t in tests:
        url = get_download_url(t.version, t.platform)
        asserts.equals(env, t.expected, url)

    return unittest.end(env)

standalone_toolchain_download_url_test = unittest.make(_standalone_toolchain_download_url_test)

def utils_test_suite(name):
    return unittest.suite(
        name,
        include_developer_search_paths_test,
        standalone_toolchain_download_url_test,
    )

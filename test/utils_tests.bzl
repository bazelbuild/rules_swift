"""Tests for `utils` module."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//swift/internal:developer_dirs.bzl", "developer_dirs_linkopts")

# buildifier: disable=bzl-visibility
load("//swift/internal:utils.bzl", "include_developer_search_paths")

# buildifier: disable=bzl-visibility
load("//swift/internal/extensions:standalone_toolchain.bzl", "get_download_url")

# buildifier: disable=bzl-visibility
load(
    "//swift/internal/extensions:swift_sdk_releases.bzl",
    "SWIFT_SDK_RELEASES",
    "static_linux_sdk_download_url",
    "swift_sdk_download_url",
)

# buildifier: disable=bzl-visibility
load(
    "//swift/internal/extensions:swift_sdks.bzl",
    "static_linux_linkopts_from_args",
)

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

def _developer_dirs_linkopts_test(ctx):
    env = unittest.begin(ctx)

    tests = [
        struct(
            msg = "Empty developer dirs should not emit any linker flags",
            developer_dirs = [],
            exp = [],
        ),
        struct(
            msg = "Non-platform developer dirs should emit only framework search paths",
            developer_dirs = [
                struct(
                    developer_path_label = "developer",
                    path = "/tmp/dev-frameworks",
                ),
            ],
            exp = [
                "-F/tmp/dev-frameworks",
            ],
        ),
        struct(
            msg = "Platform developer dirs should emit swift lib and framework search paths",
            developer_dirs = [
                struct(
                    developer_path_label = "platform",
                    path = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks",
                ),
            ],
            exp = [
                "-L/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib",
                "-F/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks",
            ],
        ),
    ]

    for t in tests:
        actual = developer_dirs_linkopts(t.developer_dirs)
        asserts.equals(env, t.exp, actual, t.msg)

    return unittest.end(env)

developer_dirs_linkopts_test = unittest.make(_developer_dirs_linkopts_test)

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

def _swift_sdk_download_url_test(ctx):
    env = unittest.begin(ctx)

    tests = [
        struct(
            version = "6.3.2",
            sdk = "wasm",
            expected = "https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz",
        ),
        struct(
            version = "6.3.2",
            sdk = "android",
            expected = "https://download.swift.org/swift-6.3.2-release/android-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_android.artifactbundle.tar.gz",
        ),
    ]
    for t in tests:
        asserts.equals(env, t.expected, swift_sdk_download_url(t.version, t.sdk))

    return unittest.end(env)

swift_sdk_download_url_test = unittest.make(_swift_sdk_download_url_test)

def _static_linux_sdk_release_metadata_test(ctx):
    env = unittest.begin(ctx)

    static_linux_release = SWIFT_SDK_RELEASES["6.3.2"]["static_linux"]
    asserts.equals(
        env,
        "3fd798bef6f4408f1ea5a6f94ce4d4052830c4326ab85ebc04f983f01b3da407",
        static_linux_release["sha256"],
    )
    asserts.equals(env, "0.1.0", static_linux_release["version"])

    asserts.equals(
        env,
        "https://download.swift.org/swift-6.3.2-release/static-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz",
        static_linux_sdk_download_url("6.3.2", "0.1.0"),
    )

    return unittest.end(env)

static_linux_sdk_release_metadata_test = unittest.make(_static_linux_sdk_release_metadata_test)

def _static_linux_linkopts_from_args_test(ctx):
    env = unittest.begin(ctx)

    args = [
        "-static",
        "-lswiftCore",
        "-lswift_RegexParser",
        "-Xlinker",
        "-undefined=pthread_self",
        "-Xlinker",
        "-undefined=pthread_once",
        "-Xlinker",
        "-undefined=pthread_key_create",
        "-ldispatch",
        "-lBlocksRuntime",
        "-lpthread",
        "-ldl",
        "-lc++",
        "-lm",
    ]

    asserts.equals(
        env,
        [
            "external/static_linux_sdk/swift_static/linux-static/x86_64/swiftrt.o",
            "-Lexternal/static_linux_sdk/swift_static/linux-static",
            "-static",
            "-lswiftCore",
            "-lswift_RegexParser",
            "-Xlinker",
            "-undefined=pthread_self",
            "-Xlinker",
            "-undefined=pthread_once",
            "-Xlinker",
            "-undefined=pthread_key_create",
            "-ldispatch",
            "-lBlocksRuntime",
            "-lpthread",
            "-ldl",
            "-lc++",
            "-lm",
        ],
        static_linux_linkopts_from_args(
            arch = "x86_64",
            args = args,
            linux_static_dir = "external/static_linux_sdk/swift_static/linux-static",
        ),
    )

    asserts.equals(
        env,
        [
            "-Lexternal/static_linux_sdk/swift_static/linux-static",
            "-Xlinker",
            "--future-linker-arg",
            "-Xlinker",
        ],
        static_linux_linkopts_from_args(
            arch = "x86_64",
            args = [
                "-Xlinker",
                "--future-linker-arg",
                "-Xlinker",
            ],
            include_swiftrt = False,
            linux_static_dir = "external/static_linux_sdk/swift_static/linux-static",
        ),
    )

    return unittest.end(env)

static_linux_linkopts_from_args_test = unittest.make(_static_linux_linkopts_from_args_test)

def utils_test_suite(name):
    return unittest.suite(
        name,
        developer_dirs_linkopts_test,
        include_developer_search_paths_test,
        static_linux_linkopts_from_args_test,
        static_linux_sdk_release_metadata_test,
        standalone_toolchain_download_url_test,
        swift_sdk_download_url_test,
    )

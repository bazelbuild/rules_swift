load("//swift:swift.bzl", "swift_test")

licenses(["notice"])

swift_test(
    name = "xctest",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    env = {
        "XCTEST_ENV_VAR": "TRUE",
        "XCTEST_BINDIR_ENV_VAR": "$(BINDIR)",
    },
)

swift_test(
    name = "xctest_tsan",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    env = {
        "XCTEST_ENV_VAR": "TRUE",
        "XCTEST_BINDIR_ENV_VAR": "$(BINDIR)",
    },
    features = ["tsan"],
)

swift_test(
    name = "xctest_asan",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    env = {
        "XCTEST_ENV_VAR": "TRUE",
        "XCTEST_BINDIR_ENV_VAR": "$(BINDIR)",
    },
    features = ["asan"],
)

swift_test(
    name = "xctest_ubsan",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    env = {
        "XCTEST_ENV_VAR": "TRUE",
        "XCTEST_BINDIR_ENV_VAR": "$(BINDIR)",
    },
    features = ["ubsan"],
)

swift_test(
    name = "xctest_tsan_and_ubsan",
    srcs = [
        "SimpleTests.swift",
        "main.swift",
    ],
    env = {
        "XCTEST_ENV_VAR": "TRUE",
        "XCTEST_BINDIR_ENV_VAR": "$(BINDIR)",
    },
    features = [
        "tsan",
        "ubsan",
    ],
)

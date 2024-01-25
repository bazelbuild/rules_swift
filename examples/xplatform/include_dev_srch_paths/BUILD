load("//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "TestHelper",
    srcs = ["TestHelper.swift"],
    always_include_developer_search_paths = True,
    module_name = "TestHelper",
)

swift_test(
    name = "DemoTestHelperTest",
    srcs = [
        "DemoTestHelperTest.swift",
        "main.swift",
    ],
    deps = [":TestHelper"],
)

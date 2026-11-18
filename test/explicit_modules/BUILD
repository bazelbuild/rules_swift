load("@rules_python//python:py_test.bzl", "py_test")

py_test(
    name = "scan_tool_paths_test",
    size = "small",
    srcs = ["scan_tool_paths_test.py"],
    data = ["//tools/explicit_modules:scan.py"],
    env = {"SCAN_PY": "$(rootpath //tools/explicit_modules:scan.py)"},
)

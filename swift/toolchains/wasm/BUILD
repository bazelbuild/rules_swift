# Selects between the WebAssembly Swift SDKs when a module declares both a
# single-threaded and a threads one.

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

constraint_setting(
    name = "threads",
    default_constraint_value = ":single_threaded",
)

constraint_value(
    name = "single_threaded",
    constraint_setting = ":threads",
)

constraint_value(
    name = "threaded",
    constraint_setting = ":threads",
)

load("@rules_shell//shell:sh_test.bzl", "sh_test")

[
    sh_test(
        name = name + "_test",
        size = "small",
        srcs = ["worker_test.sh"],
        args = [
            "$(rootpath //tools/worker:worker)",
            "$(rootpath :fake_swiftc.sh)",
            name,
        ],
        data = [
            "fake_swiftc.sh",
            "//tools/worker",
        ],
        target_compatible_with = select({
            "@platforms//os:windows": ["@platforms//:incompatible"],
            "//conditions:default": [],
        }),
    )
    for name in [
        "module_outputs_survive_failure",
        "source_changes_keep_dependencies",
        "changed_dependency_digest",
        "changed_arguments",
        "changed_universal_arguments",
        "missing_digest",
        "missing_input_record",
        "corrupt_input_record",
        "failed_dependency_change",
    ]
]

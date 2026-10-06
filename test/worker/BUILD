load(":worker_test.bzl", "worker_test")

[
    worker_test(
        name = name + "_test",
        size = "medium",
        scenario = name,
        target_compatible_with = select({
            "@platforms//os:windows": ["@platforms//:incompatible"],
            "//conditions:default": [],
        }),
    )
    for name in [
        "module_outputs_survive_failure",
        "changed_dependency_digest",
        "changed_dependency_digest_without_hashing",
        "changed_arguments",
        "changed_universal_arguments",
        "missing_digest",
        "removed_dependency_input",
        "missing_input_record",
        "corrupt_input_record",
        "atomic_input_record",
        "failed_dependency_change",
    ]
]

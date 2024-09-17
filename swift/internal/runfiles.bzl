def include_runfiles_constants(label, actions, all_deps):
    """
    TODO: Do this the right way.
    """
    matches = [dep for dep in all_deps if dep.label == Label("@build_bazel_rules_swift//swift/runfiles:runfiles")]
    if len(matches) > 0:
        repo_name_file = actions.declare_file("Runfiles+Constants.swift")
        actions.write(
            output = repo_name_file,
            content = """
            internal enum BazelRunfilesConstants {{
                static let currentRepository = "{}"
            }}
            """.format(label.workspace_name),
        )
        return [repo_name_file]
    return []
"""Registers the actions that generate `.grpc.swift` files from `.proto` files.

Args:
    package: Package.swift manifest file that will be used when installing your dependencies.
    package_resolved: Package.resolved file that will be used when resolving version of your dependencies.
    symlink_build_path: When this option True the .build path of WORKSPACE will be symlinked to repository.
    debug: To Debug this rule set this attribute to True
Returns:
    None
"""

def _swift_package_install_impl(ctx):
    # To debug make this
    QUIET = ctx.attr.debug != True

    ctx.symlink(ctx.attr.package, ctx.path("Package.swift"))
    ctx.symlink(ctx.attr.package_resolved, ctx.path("Package.resolved"))

    if ctx.attr.symlink_build_path:
        workspace_dir = ctx.path(ctx.attr.package).dirname

        # May be we should get .build path through attributes if necessary
        ctx.symlink(ctx.path(str(workspace_dir) + "/.build"), ctx.path(".build"))

    if not QUIET:
        ctx.execute(
            ['swift', '--version'], 
            quiet = False
        )

    ctx.file(
        "resolve.sh",
        content = """
        swift package resolve
        swift package show-dependencies --format=json > depgraph.json
        """,
        executable = True,
    )
    ctx.report_progress("Resolving swift packages.")
    result = ctx.execute(
        [ctx.path("resolve.sh")],
        quiet = QUIET,
    )
    if result.return_code:
        fail("Installing swift packages failed: %s (%s)" % (result.stdout, result.stderr))

    ctx.report_progress("Building packages and generating build file tree.")
    swift_path = ctx.which("swift")
    ar_path = ctx.which("ar")
    result = ctx.execute(
        [
            "swift",
            ctx.path(ctx.attr._resolver),
            ctx.name,
            swift_path,
            ar_path,
            ".build/release",
        ],
        quiet = QUIET,
    )
    if result.return_code:
        fail("Building packages and generating build file tree failed: %s (%s)" % (result.stdout, result.stderr))

swift_package_install = repository_rule(
    implementation = _swift_package_install_impl,
    attrs = {
        "package": attr.label(
            mandatory = True,
            allow_files = [".swift"],
            doc = """
            Package.swift manifest file that will be used when installing your dependencies.
            Each dependency specifies a source URL and version requirements. 
            The source URL is a URL accessible to the current user that resolves to a Git repository. 
            The version requirements, which follow Semantic Versioning (SemVer) conventions, 
            are used to determine which Git tag to check out and use to build the dependency. 
            See: https://swift.org/package-manager "Importing Dependencies" section.
            """,
        ),
        "package_resolved": attr.label(
            mandatory = True,
            allow_files = [".resolved"],
            doc = """
            The package manager records the result of dependency resolution in a Package.resolved file in the top-level of the package, 
            and when this file is already present in the top-level, it is used when performing dependency resolution, 
            rather than the package manager finding the latest eligible version of each package. 
            Running swift package update updates all dependencies to the latest eligible versions and updates the Package.resolved file accordingly.
            Note: Hermeticity and Reproducibility of your build depends on this file.
            See: https://github.com/apple/swift-package-manager/blob/master/Documentation/Usage.md#resolving-versions-packageresolved-file
            """,
        ),
        "symlink_build_path": attr.bool(
            default = False,
            doc = """
            When this attribute is true the .build directory of your workspace will be symlinked into repository directory
            which will speed up resolution and build process since package manager will be using cache and existing files on .build path.

            IMPORTANT: This feature requires managed_directories feature of Bazel which introduced in Bazel version 26.0
            """,
        ),
        "debug": attr.bool(
            default = False,
            doc = """
            To debug this rule you can set this property to true.
            """,
        ),
        "_resolver": attr.label(
            default = ":swift_package_install.swift",
        ),
    },
)

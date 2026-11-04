"""Checks on which modules may use the `swift` module extension."""

def non_dev_toolchain_modules(modules, is_dev_dependency):
    """Returns the names of non-root modules with a non-dev-dependency `toolchain` tag.

    Args:
        modules: The `module_ctx.modules` list.
        is_dev_dependency: A function that takes a tag and returns whether it
            was declared with `dev_dependency = True`.

    Returns:
        A list of module names that should not be using the extension.
    """
    names = []
    for mod in modules:
        if mod.is_root:
            continue
        for tag in mod.tags.toolchain:
            if not is_dev_dependency(tag):
                names.append(mod.name)
                break
    return names

load("//swift:swift.bzl", "SwiftInfo")

def macro_with_doc(name):
    """This macro does nothing.

    Args:
        name: A `string` value.
    """
    return SwiftInfo

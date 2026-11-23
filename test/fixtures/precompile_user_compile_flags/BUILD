load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//test:transitions.bzl", "transition_binary")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

swift_interop_hint(
    name = "Defines_hint",
    module_name = "Defines",
    tags = FIXTURE_TAGS,
)

swift_interop_hint(
    name = "SearchPaths_hint",
    module_name = "SearchPaths",
    tags = FIXTURE_TAGS,
)

swift_interop_hint(
    name = "NoCoptsTokenization_hint",
    module_name = "NoCoptsTokenization",
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "Defines",
    srcs = [
        "Defines.c",
        "Defines.h",
    ],
    hdrs = ["Defines.h"],
    aspect_hints = [":Defines_hint"],
    copts = [
        "-DFIXTURE_FROM_COPTS=1",
        "-DFIXTURE_FROM_COPTS_WITH_SPACES=rules\\ swift\\ fixture",
        "-DFIXTURE_FROM_QUOTED_COPTS='quoted rules swift fixture'",
        "-include$(execpath :Defines.h)",
    ],
    local_defines = ["FIXTURE_FROM_LOCAL_DEFINES=1"],
    tags = FIXTURE_TAGS,
)

_SEARCH_PATHS_DIR = package_name() + "/search_paths"

cc_library(
    name = "SearchPaths",
    srcs = ["SearchPaths.c"],
    # The search path headers are module headers so that the layering check
    # accepts their includes. They are found only through the copts below.
    hdrs = [
        "SearchPaths.h",
        "search_paths/include_dir/search_path_from_include.h",
        "search_paths/quote_dir/search_path_from_iquote.h",
        "search_paths/separated_dir/search_path_from_separated.h",
        "search_paths/system_dir/search_path_from_isystem.h",
    ],
    aspect_hints = [":SearchPaths_hint"],
    copts = [
        "-I{}/include_dir".format(_SEARCH_PATHS_DIR),
        "-iquote{}/quote_dir".format(_SEARCH_PATHS_DIR),
        "-isystem{}/system_dir".format(_SEARCH_PATHS_DIR),
        # Separated forms. The define after each one must still reach the PCM.
        "-isystem",
        "{}/separated_dir".format(_SEARCH_PATHS_DIR),
        "-DSEARCH_PATHS_AFTER_SEPARATED=1",
        # A make variable is skipped together with its flag.
        "-I",
        "$(GENDIR)/{}/does_not_exist".format(_SEARCH_PATHS_DIR),
        "-DSEARCH_PATHS_AFTER_MAKE_VARIABLE=1",
    ],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "NoCoptsTokenization",
    srcs = [
        "NoCoptsTokenization.c",
        "NoCoptsTokenization.h",
    ],
    hdrs = ["NoCoptsTokenization.h"],
    aspect_hints = [":NoCoptsTokenization_hint"],
    copts = ["-DFIXTURE_NO_COPTS_TOKENIZATION=rules swift fixture"],
    features = ["no_copts_tokenization"],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "user",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
    deps = [
        ":Defines",
        ":NoCoptsTokenization",
        ":SearchPaths",
    ],
)

transition_binary(
    name = "user_explicit_modules",
    tags = FIXTURE_TAGS,
    target = ":user",
    # TODO: Remove when we support explicit modules on Linux
    target_compatible_with = ["@platforms//os:macos"],
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
    ],
)

transition_binary(
    name = "user_explicit_modules_layering_check",
    tags = FIXTURE_TAGS,
    target = ":user",
    # TODO: Remove when we support explicit modules on Linux
    target_compatible_with = ["@platforms//os:macos"],
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.layering_check_for_c_deps",
    ],
)

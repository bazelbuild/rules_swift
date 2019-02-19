# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Generates Swift-compatible module maps for direct C dependencies of Swift targets."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":api.bzl", "swift_common")
load(":derived_files.bzl", "derived_files")
load(":features.bzl", "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD")
load(":providers.bzl", "SwiftClangModuleInfo", "SwiftToolchainInfo")

def _explicit_module_name(tags):
    """Returns an explicit module name specified by a tag of the form `"swift_module=Foo"`.

    Since tags are unprocessed strings, nothing prevents the `swift_module` tag from being listed
    multiple times on the same target with different values. For this reason, the aspect uses the
    _last_ occurrence that it finds in the list.

    Args:
        tags: The list of tags from the `cc_library` target to which the aspect is being applied.

    Returns:
        The desired module name if it was present in `tags`, or `None`.
    """
    module_name = None
    for tag in tags:
        if tag.startswith("swift_module="):
            _, _, module_name = tag.partition("=")
    return module_name

def _header_path(file, module_map, workspace_relative):
    """Returns the path to a header file as it should be written into the module map.

    Args:
        file: A `File` representing the header whose path should be returned.
        module_map: A `File` representing the module map being written, which is used during path
            relativization if necessary.
        workspace_relative: A Boolean value indicating whether the path should be
            workspace-relative or module-map-relative.

    Returns:
        The path to the header file, relative to either the workspace or the module map as
        requested.
    """

    # If the module map is workspace-relative, then the file's path is what we want.
    if workspace_relative:
        return file.path

    # Otherwise, since the module map is generated, we need to get the full path to it rather than
    # just its short path (that is, the path starting with bazel-out/). Then, we can simply walk up
    # the same number of parent directories as there are path segments, and append the header
    # file's path to that.
    num_segments = len(paths.dirname(module_map.path).split("/"))
    return ("../" * num_segments) + file.path

def _write_module_map(
        actions,
        module_map,
        module_name,
        hdrs = [],
        textual_hdrs = [],
        workspace_relative = False):
    """Writes the content of the module map to a file.

    Args:
        actions: The actions object from the aspect context.
        module_map: A `File` representing the module map being written.
        module_name: The name of the module being generated.
        hdrs: The value of `attr.hdrs` for the target being written (which is a list of targets
            that are either source files or generated files).
        textual_hdrs: The value of `attr.textual_hdrs` for the target being written (which is a
            list of targets that are either source files or generated files).
        workspace_relative: A Boolean value indicating whether the path should be
            workspace-relative or module-map-relative.
    """
    content = "module {} {{\n".format(module_name)

    # TODO(allevato): Should we consider moving this to an external tool to avoid the analysis time
    # expansion of these depsets? We're doing this in the initial version because these sets tend
    # to be very small.
    for target in hdrs:
        content += "".join([
            '    header "{}"\n'.format(_header_path(header, module_map, workspace_relative))
            for header in target.files.to_list()
        ])
    for target in textual_hdrs:
        content += "".join([
            '    textual header "{}"\n'.format(_header_path(header, module_map, workspace_relative))
            for header in target.files.to_list()
        ])
    content += "    export *\n"
    content += "}\n"

    actions.write(output = module_map, content = content)

def _swift_c_module_aspect_impl(target, aspect_ctx):
    # Do nothing if the target already propagates `SwiftClangModuleInfo`.
    if SwiftClangModuleInfo in target:
        return []

    attr = aspect_ctx.rule.attr

    # If there's an explicit module name, use it; otherwise, auto-derive one using the usual
    # derivation logic for Swift targets.
    module_name = _explicit_module_name(attr.tags)
    if not module_name:
        if "/" in target.label.name or "+" in target.label.name:
            return []
        module_name = swift_common.derive_module_name(target.label)

    # Determine if the toolchain requires module maps to use workspace-relative paths or not.
    toolchain = aspect_ctx.attr._toolchain_for_aspect[SwiftToolchainInfo]
    feature_configuration = swift_common.configure_features(
        requested_features = aspect_ctx.features,
        swift_toolchain = toolchain,
        unsupported_features = aspect_ctx.disabled_features,
    )
    workspace_relative = swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
    )

    # It's not great to depend on the rule name directly, but we need to access the exact `hdrs`
    # and `textual_hdrs` attributes (which may not be propagated distinctly by a provider) and
    # also make sure that we don't pick up rules like `objc_library` which already handle module
    # map generation.
    if aspect_ctx.rule.kind == "cc_library":
        module_map = derived_files.module_map(aspect_ctx.actions, target.label.name)
        _write_module_map(
            actions = aspect_ctx.actions,
            hdrs = attr.hdrs,
            module_map = module_map,
            module_name = module_name,
            textual_hdrs = attr.textual_hdrs,
            workspace_relative = workspace_relative,
        )

        # Ensure that public headers from libraries that this `cc_library` depend on are also
        # available to the actions.
        transitive_headers_sets = []
        for dep in attr.deps:
            if CcInfo in dep:
                transitive_headers_sets.append(dep[CcInfo].compilation_context.headers)

        compilation_context = target[CcInfo].compilation_context
        return [SwiftClangModuleInfo(
            transitive_compile_flags = depset(
                # TODO(b/124373197): Expanding these depsets isn't great, but it's temporary
                # until we get rid of this provider completely.
                direct = [
                    "-isystem{}".format(include)
                    for include in compilation_context.system_includes.to_list()
                ] + [
                    "-iquote{}".format(include)
                    for include in compilation_context.quote_includes.to_list()
                ] + [
                    "-I{}".format(include)
                    for include in compilation_context.includes.to_list()
                ],
            ),
            transitive_defines = compilation_context.defines,
            transitive_headers = depset(transitive = (
                transitive_headers_sets +
                [target.files for target in attr.hdrs] +
                [target.files for target in attr.textual_hdrs]
            )),
            transitive_modulemaps = depset(direct = [module_map]),
        )]

    # TODO(b/118311259): Figure out how to handle transitive dependencies, in case a C-only
    # module incldues headers from another C-only module. We currently have a lot of targets with
    # labels that clash when mangled into a Swift module name, so we need to figure out how to
    # handle those (either by adding the `swift_module` tag to them, or opting them in some other
    # way).
    return []

swift_c_module_aspect = aspect(
    attrs = swift_common.toolchain_attrs(toolchain_attr_name = "_toolchain_for_aspect"),
    doc = """
Generates Swift-compatible module maps for direct `cc_library` dependencies.

The modules generated by this aspect have names that are automatically derived from the label of
the `cc_library` target, using the same logic used to derive the module names for Swift targets.

This aspect is an implementation detail of the Swift build rules and is not meant to be attached
to other rules or run independently.
""",
    implementation = _swift_c_module_aspect_impl,
)

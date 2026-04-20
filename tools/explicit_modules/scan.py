#!/usr/bin/env python3

from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional, TextIO
import collections
import io
import json
import os
import re
import subprocess
import sys
import tempfile


_SDK_CONSTRAINTS = {
    "MacOSX": ["@platforms//os:macos"],
    "iPhoneOS": [
        "@platforms//os:ios",
        "@build_bazel_apple_support//constraints:device",
    ],
    "iPhoneSimulator": [
        "@platforms//os:ios",
        "@build_bazel_apple_support//constraints:simulator",
    ],
    "AppleTVOS": [
        "@platforms//os:tvos",
        "@build_bazel_apple_support//constraints:device",
    ],
    "AppleTVSimulator": [
        "@platforms//os:tvos",
        "@build_bazel_apple_support//constraints:simulator",
    ],
    "WatchOS": [
        "@platforms//os:watchos",
        "@build_bazel_apple_support//constraints:device",
    ],
    "WatchSimulator": [
        "@platforms//os:watchos",
        "@build_bazel_apple_support//constraints:simulator",
    ],
    "XROS": [
        "@platforms//os:visionos",
        "@build_bazel_apple_support//constraints:device",
    ],
    "XRSimulator": [
        "@platforms//os:visionos",
        "@build_bazel_apple_support//constraints:simulator",
    ],
}
TARGET_FORMATS = {
    "macosx": "arm64-apple-macos{ver}",
    "iphoneos": "arm64-apple-ios{ver}",
    "iphonesimulator": "arm64-apple-ios{ver}-simulator",
    "watchos": "arm64-apple-watchos{ver}",
    "watchsimulator": "arm64-apple-watchos{ver}-simulator",
    "appletvos": "arm64-apple-tvos{ver}",
    "appletvsimulator": "arm64-apple-tvos{ver}-simulator",
    "xros": "arm64-apple-xros{ver}",
    "xrsimulator": "arm64-apple-xros{ver}-simulator",
}

_HEADER = """\
load(
    "@build_bazel_rules_swift//swift:swift.bzl",
    "apple_sdk_clang_module",
    "swift_library_group",
)

package(default_visibility = ["//visibility:public"])
"""


def _canonical_name(name: str, sdk: str, module_type: str) -> str:
    suffix = ""
    if module_type == "clang":
        suffix = "_clang"
    return f"{sdk}_{name}{suffix}"


def _render_clang_aliases(modules: list[str], sdk: str, out: TextIO):
    for module in modules:
        out.write("\n")
        out.write("alias(\n")
        out.write(f'    name = "{_canonical_name(module, sdk, "alias")}",\n')
        out.write(f'    actual = ":{_canonical_name(module, sdk, "clang")}",\n')
        out.write(")\n")


def _render_all_modules_group(
    all_module_names: set[str],
    sdk: str,
    out: TextIO,
) -> None:
    out.write("\n")
    out.write("swift_library_group(\n")
    out.write(f'    name = "{sdk}_all_modules",\n')
    out.write("    deps = [\n")
    for name in sorted(all_module_names):
        out.write(f'        ":{sdk}_{name}",\n')
    out.write("    ],\n")
    out.write(")\n")


@dataclass
class _Module:
    def __init__(self, name, sdk, module_type, direct_dependencies, module_map_path):
        self.name: str = name
        self.sdk: str = sdk
        self.module_type: str = module_type
        self.direct_dependencies: list[str] = sorted(
            set(
                _canonical_name(dep_name, sdk, dep_type)
                for dep_type, dep_name in direct_dependencies
            )
        )
        self.module_map_path: Optional[str] = module_map_path

    def __repr__(self):
        return f"{self.name=} {self.module_type=}"

    def __lt__(self, other):
        return (self.name, self.module_type) < (
            other.name,
            other.module_type,
        )

    def render_target(self, out: TextIO) -> None:
        if self.module_type == "clang":
            assert self.module_map_path
            out.write("\n")
            out.write("apple_sdk_clang_module(\n")
            out.write(
                f'    name = "{_canonical_name(self.name, self.sdk, self.module_type)}",\n'
            )
            out.write(f'    module_name = "{self.name}",\n')
            out.write(f'    system_module_map = "{self.module_map_path}",\n')
            if self.direct_dependencies:
                out.write("    deps = [\n")
                for dep_name in self.direct_dependencies:
                    out.write(f'        ":{dep_name}",\n')
                out.write("    ],\n")
            out.write(")\n")
        elif self.module_type == "swift":
            out.write("\n")
            out.write("swift_library_group(\n")
            out.write(
                f'    name = "{_canonical_name(self.name, self.sdk, self.module_type)}",\n'
            )
            if self.direct_dependencies:
                out.write("    deps = [\n")
                for dep_name in self.direct_dependencies:
                    out.write(f'        ":{dep_name}",\n')
                out.write("    ],\n")
            out.write(")\n")
        else:
            raise SystemExit(
                f"unexpected module type: {self.module_type} for {self.name}"
            )


def _parse_output(
    *,
    output: dict[str, Any],
    sdk: str,
    developer_dir: str,
    sdkroot: str,
) -> tuple[list[_Module], dict[str, set[str]]]:
    modules = output["modules"][2:]  # Skip stub file module

    all_modules = []
    modules_by_type = collections.defaultdict(set)
    for i in range(0, len(modules), 2):  # Entries come in pairs
        module = modules[i]
        assert len(module) == 1

        module_type, module_name = next(iter(module.items()))
        modules_by_type[module_type].add(module_name)
        module = modules[i + 1]
        details = module["details"][module_type]
        deps = []
        for dep in module["directDependencies"] + details.get(
            "swiftOverlayDependencies", []
        ):
            deps.extend(dep.items())

        all_modules.append(
            _Module(
                module_name,
                sdk,
                module_type,
                deps,
                details.get("moduleMapPath", "")
                .replace(sdkroot, "__BAZEL_XCODE_SDKROOT__")
                .replace(developer_dir, "__BAZEL_XCODE_DEVELOPER_DIR__"),
            )
        )

    return sorted(all_modules), modules_by_type


def _get_deployment_target(sdk: str, sdk_path: Path) -> str:
    settings = sdk_path / "SDKSettings.json"
    with open(settings) as f:
        output = json.load(f)

    return output["SupportedTargets"][sdk.lower()]["DefaultDeploymentTarget"]


# Error patterns we are ignoring:
#
#   <unknown>:0: error: clang dependency scanning failure: ...
#                         ... error: module 'X' is incompatible with feature 'swift'
#   X-<hash>.input:1:1: fatal error: could not build module 'X'
#   stub.swift:1:8: error: unable to resolve module dependency: 'X'
#   .../X.swiftinterface:7:19: error: Unable to find module dependency: 'X'
#
_IGNORED_ERRORS = (
    re.compile(r"[Uu]nable to (?:resolve|find) module dependency: '[^']+'"),
    re.compile(r"clang dependency scanning failure"),
    re.compile(r"could not build module '[^']+'"),
    re.compile(r"error: module '[^']+' is incompatible with feature 'swift'"),
)


def _scan(
    *,
    sdk: str,
    modules: set[str],
    sdk_path: Path,
    target: str,
    framework_search_paths: list[Path],
) -> dict[str, Any]:
    """Run `swiftc -scan-dependencies` once.

    Modules whose import fails are reported as `unable to resolve module
    dependency: 'X'` on stderr and simply don't appear in the JSON — we
    accept that. Any other stderr `error:` line, or a non-zero exit, is
    fatal.
    """
    with tempfile.TemporaryDirectory(prefix=f"scan_{sdk}_") as tmp:
        workdir = Path(tmp)
        stub = workdir / "stub.swift"
        out_json = workdir / "scan.json"
        stub.write_text(
            "\n".join(f"import {m}" for m in sorted(modules)) + "\n",
        )
        cmd = [
            "xcrun",
            "swiftc",
            "-scan-dependencies",
            str(stub),
            "-sdk",
            str(sdk_path),
            "-target",
            target,
            "-o",
            str(out_json),
        ] + [f"-F{p}" for p in framework_search_paths]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(
                f"[{sdk}] swiftc -scan-dependencies exited "
                f"{res.returncode}:\n{res.stderr}"
            )

        # -scan-dependencies exits 0 even if some imports fail.
        errors = [
            l
            for l in res.stderr.splitlines()
            if "error:" in l and not any(p.search(l) for p in _IGNORED_ERRORS)
        ]
        if errors:
            raise RuntimeError(
                f"[{sdk}] swiftc -scan-dependencies reported unexpected errors:\n"
                + "\n".join(errors)
            )

        return json.loads(out_json.read_text())


def _discover_all_modules(developer_dir: Path, sdk: str) -> tuple[str, set[str]]:
    sdk_path = developer_dir / f"Platforms/{sdk}.platform/Developer/SDKs/{sdk}.sdk"
    platform_search_path = (
        developer_dir / f"Platforms/{sdk}.platform/Developer/Library/Frameworks"
    )
    framework_search_paths = [
        platform_search_path,
        sdk_path / f"System/Library/Frameworks",
    ]
    library_search_paths = [
        sdk_path / "usr/lib/swift",
    ]

    modules = set()
    for directory in set(framework_search_paths + library_search_paths):
        for x in directory.iterdir():
            if not x.is_dir():
                continue
            if x.suffix == ".swiftmodule":
                modules.add(x.stem)
            elif x.suffix == ".framework":
                if (x / "Modules/module.modulemap").exists() or (
                    x / "Modules" / (x.stem + ".swiftmodule")
                ).exists():
                    modules.add(x.stem)

    target = TARGET_FORMATS[sdk.lower()].format(
        ver=_get_deployment_target(sdk, sdk_path),
    )
    scan_output = _scan(
        sdk=sdk,
        modules=modules,
        sdk_path=sdk_path,
        target=target,
        framework_search_paths=framework_search_paths,
    )

    all_modules, modules_by_type = _parse_output(
        output=scan_output,
        sdk=sdk,
        developer_dir=developer_dir.as_posix(),
        sdkroot=sdk_path.as_posix(),
    )
    clang_only_modules = sorted(modules_by_type["clang"] - modules_by_type["swift"])

    buf = io.StringIO()
    for module in all_modules:
        module.render_target(buf)
    _render_clang_aliases(clang_only_modules, sdk, buf)

    all_module_names = modules_by_type["swift"] | modules_by_type["clang"]
    _render_all_modules_group(all_module_names, sdk, buf)
    return buf.getvalue(), all_module_names


def _main() -> None:
    developer_dir = Path(os.environ["DEVELOPER_DIR"])

    requested_sdks = sys.argv[1:]
    if requested_sdks:
        unknown = [s for s in requested_sdks if s not in _SDK_CONSTRAINTS]
        if unknown:
            raise SystemExit(
                f"error: unknown SDK(s): '{unknown}'. Valid options are: {sorted(_SDK_CONSTRAINTS)}"
            )
        sdk_names = sorted(set(requested_sdks))
    else:
        sdk_names = sorted(_SDK_CONSTRAINTS.keys())

    buf = io.StringIO()
    buf.write(_HEADER)
    for sdk in sdk_names:
        constraints = _SDK_CONSTRAINTS[sdk]
        buf.write("\n")
        buf.write("config_setting(\n")
        buf.write(f'    name = "{sdk}_sdk",\n')
        buf.write("    constraint_values = [\n")
        for c in constraints:
            buf.write(f'        "{c}",\n')
        buf.write("    ],\n")
        buf.write('    visibility = ["//visibility:private"],\n')
        buf.write(")\n")

    all_modules_by_sdk: dict[str, set[str]] = {}
    all_modules: set[str] = set()
    per_sdk_text: dict[str, str] = {}
    with ThreadPoolExecutor(max_workers=len(sdk_names)) as pool:
        futures = {
            pool.submit(_discover_all_modules, developer_dir, sdk): sdk
            for sdk in sdk_names
        }
        for fut in as_completed(futures):
            sdk = futures[fut]
            output, modules = fut.result()
            per_sdk_text[sdk] = output
            all_modules_by_sdk[sdk] = modules
            all_modules |= modules

    for sdk in sdk_names:
        buf.write(per_sdk_text[sdk])

    for module in sorted(all_modules):
        buf.write("\n")
        buf.write("alias(\n")
        buf.write(f'    name = "{module}",\n')
        buf.write("    actual = select({\n")
        for sdk in sdk_names:
            if module in all_modules_by_sdk[sdk]:
                buf.write(
                    f'        ":{sdk}_sdk": ":{_canonical_name(module, sdk, "alias")}",\n'
                )
        buf.write("    }),\n")
        buf.write(")\n")

    buf.write("\n")
    buf.write("alias(\n")
    buf.write('    name = "all_modules",\n')
    buf.write("    actual = select({\n")
    for sdk in sdk_names:
        if all_modules_by_sdk.get(sdk):
            buf.write(f'        ":{sdk}_sdk": ":{sdk}_all_modules",\n')
    buf.write("    }),\n")
    buf.write(")\n")

    with open("BUILD.bazel", "w") as f:
        f.write(buf.getvalue())

    with open("module_names.json", "w") as f:
        json.dump(sorted(all_modules), f, indent=2)


if __name__ == "__main__":
    _main()

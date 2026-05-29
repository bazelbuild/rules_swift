#!/usr/bin/env python3

from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, TextIO
import argparse
import io
import json
import os
import subprocess
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

_DEFAULT_EXCLUDED_MODULES = {
    "AppleTVSimulator": {"CoreAudio_Private"},
    "iPhoneSimulator": {"CoreAudio_Private"},
    "WatchOS": {"BrowserEngineKit"},
    "WatchSimulator": {"BrowserEngineKit", "CoreAudio_Private"},
    "XROS": {"AccessoryTransportExtension"},
    "XRSimulator": {"AccessoryTransportExtension"},
}

_TARGETS_PER_SDK = {
    "macosx": [
        ("@platforms//cpu:arm64", "arm64-apple-macos{ver}"),
        ("@platforms//cpu:arm64e", "arm64e-apple-macos{ver}"),
        ("@platforms//cpu:x86_64", "x86_64-apple-macos{ver}"),
    ],
    "iphoneos": [
        ("@platforms//cpu:arm64", "arm64-apple-ios{ver}"),
        ("@platforms//cpu:arm64e", "arm64-apple-ios{ver}"),
    ],
    "iphonesimulator": [
        ("@platforms//cpu:arm64", "arm64-apple-ios{ver}-simulator"),
        ("@platforms//cpu:x86_64", "x86_64-apple-ios{ver}-simulator"),
    ],
    "watchos": [
        ("@platforms//cpu:arm64", "arm64-apple-watchos{ver}"),
        ("@platforms//cpu:arm64_32", "arm64_32-apple-watchos{ver}"),
        ("@platforms//cpu:arm64e", "arm64e-apple-watchos{ver}"),
    ],
    "watchsimulator": [
        ("@platforms//cpu:arm64", "arm64-apple-watchos{ver}-simulator"),
        ("@platforms//cpu:x86_64", "x86_64-apple-watchos{ver}-simulator"),
    ],
    "appletvos": [
        ("@platforms//cpu:arm64", "arm64-apple-tvos{ver}"),
    ],
    "appletvsimulator": [
        ("@platforms//cpu:arm64", "arm64-apple-tvos{ver}-simulator"),
        ("@platforms//cpu:x86_64", "x86_64-apple-tvos{ver}-simulator"),
    ],
    "xros": [
        ("@platforms//cpu:arm64", "arm64-apple-xros{ver}"),
        ("@platforms//cpu:arm64e", "arm64e-apple-xros{ver}"),
    ],
    "xrsimulator": [
        ("@platforms//cpu:arm64", "arm64-apple-xros{ver}-simulator"),
        ("@platforms//cpu:x86_64", "x86_64-apple-xros{ver}-simulator"),
    ],
}

_HEADER = """\
load(
    "@build_bazel_rules_swift//swift:swift.bzl",
    "swift_cross_import_overlay",
    "swift_cross_import_overlay_group",
    "system_clang_module",
    "system_module_group",
    "system_swiftinterface",
)

package(default_visibility = ["//visibility:public"])

swift_cross_import_overlay_group(name = "_empty_cross_import_overlays")

system_module_group(
    name = "_empty_all_modules",
    creates_module = False,
)
"""


def _canonical_name(name: str, sdk: str, module_type: str) -> str:
    suffix = ""
    if module_type == "clang":
        suffix = "_clang"
    return f"{sdk}_{name}{suffix}"


def _write_labels(out: TextIO, labels: set[str], indent: str = "        ") -> None:
    for label in sorted(labels):
        out.write(f'{indent}":{label}",\n')


def _normalize_system_path(path: str, *, developer_dir: str, sdkroot: str) -> str:
    return path.replace(sdkroot, "__BAZEL_XCODE_SDKROOT__").replace(
        developer_dir, "__BAZEL_XCODE_DEVELOPER_DIR__"
    )


def _write_string_attr(
    out: TextIO,
    *,
    name: str,
    values_by_cpu: dict[str, str],
) -> None:
    values = set(values_by_cpu.values())
    if len(values) == 1:
        out.write(f'    {name} = "{next(iter(values))}",\n')
        return

    out.write(f"    {name} = select({{\n")
    for cpu, value in sorted(values_by_cpu.items()):
        out.write(f'        "{cpu}": "{value}",\n')
    out.write("    }),\n")


def _write_transition_attrs(
    out: TextIO,
    *,
    sdk: str,
    sdk_version: str,
) -> None:
    out.write(f'    sdk_name = "{sdk}",\n')
    out.write(f'    sdk_version = "{sdk_version}",\n')


def _render_clang_module_groups(
    modules: list["_Module"],
    clang_only_names: set[str],
    sdk: str,
    out: TextIO,
):
    """Aggregate clang modules + their Swift overlays.

    The clang half of a module that has both a Swift and clang portion doesn't
    have its transitive Swift deps in its direct dependencies, so we have to
    add those in this aggregation target. We cannot add these always because of
    circular dependencies.

    For example:
      XCTest_clang -> Foundation_clang -> Darwin_clang
      Darwin_swift -> Darwin_clang

    If you depend on XCTest_clang from a Swift target you need to also pull in
    Darwin_swift or you will be missing some transitive dependencies. This
    aggregates that using our naming convention to strip the '_clang' suffix.
    Without these targets there is no dep from Darwin_clang to Darwin_swift.

    This affects importing targets that are clang-only, but have transitive
    deps that have both clang and Swift parts.
    """
    for module in modules:
        if module.module_type != "clang" or module.name not in clang_only_names:
            continue
        out.write("\n")
        out.write("system_module_group(\n")
        out.write(f'    name = "{_canonical_name(module.name, sdk, "alias")}",\n')
        out.write("    modules = [\n")
        deps = [_canonical_name(module.name, sdk, "clang")]
        for dep in sorted(module.all_dependencies):
            if dep.endswith("_clang"):
                deps.append(dep[: -len("_clang")])
            else:
                deps.append(dep)
        _write_labels(out, set(deps))
        out.write("    ],\n")
        out.write(")\n")


def _render_all_modules_group(
    all_module_names: set[str],
    sdk: str,
    out: TextIO,
) -> None:
    out.write("\n")
    out.write("system_module_group(\n")
    out.write(f'    name = "{sdk}_all_modules",\n')
    out.write("    creates_module = False,\n")
    out.write("    modules = [\n")
    _write_labels(out, {f"{sdk}_{name}" for name in all_module_names})
    out.write("    ],\n")
    out.write(")\n")


def _render_cross_import_overlay_targets(
    overlays: list["_CrossImportOverlay"],
    sdk: str,
    out: TextIO,
) -> None:
    for overlay in overlays:
        out.write("\n")
        out.write("swift_cross_import_overlay(\n")
        out.write(f'    name = "{overlay.target_name}",\n')
        out.write(
            f'    bystanding_module = ":{_canonical_name(overlay.bystanding_module, sdk, "alias")}",\n'
        )
        out.write(
            f'    declaring_module = ":{_canonical_name(overlay.declaring_module, sdk, "alias")}",\n'
        )
        out.write("    deps = [\n")
        _write_labels(
            out,
            {
                _canonical_name(module, sdk, "alias")
                for module in overlay.overlay_modules
            },
        )
        out.write("    ],\n")
        out.write(f'    swiftoverlay = "{overlay.swiftoverlay_path}",\n')
        out.write(")\n")

    out.write("\n")
    out.write("swift_cross_import_overlay_group(\n")
    out.write(f'    name = "{sdk}_all_cross_import_overlays",\n')
    out.write("    overlays = [\n")
    _write_labels(out, {overlay.target_name for overlay in overlays})
    out.write("    ],\n")
    out.write(")\n")


@dataclass(order=True, frozen=True)
class _CrossImportOverlay:
    declaring_module: str
    bystanding_module: str
    overlay_modules: tuple[str, ...]
    swiftoverlay_path: str
    sdk: str = field(compare=False)

    @property
    def target_name(self) -> str:
        return f"{self.sdk}_{self.declaring_module}_{self.bystanding_module}_cross_import_overlay"


@dataclass(order=True)
class _Module:
    name: str
    module_type: str
    sdk: str = field(compare=False)
    sdk_version: str = field(compare=False)
    module_map_path: str = field(compare=False)
    is_framework: bool = field(default=False, compare=False)
    swiftinterface_paths_by_cpu: dict[str, str] = field(
        default_factory=dict,
        compare=False,
    )
    deps_by_cpu: defaultdict[str, set[str]] = field(
        default_factory=lambda: defaultdict(set),
        compare=False,
    )

    def set_deps(self, cpu: str, direct_dependencies: list[tuple[str, str]]) -> None:
        self.deps_by_cpu[cpu] = set(
            _canonical_name(dep_name, self.sdk, dep_type)
            for dep_type, dep_name in direct_dependencies
        )

    def set_swiftinterface(
        self,
        *,
        cpu: str,
        is_framework: bool,
        swiftinterface_path: str,
    ) -> None:
        self.swiftinterface_paths_by_cpu[cpu] = swiftinterface_path
        self.is_framework = self.is_framework or is_framework

    @property
    def all_dependencies(self) -> set[str]:
        return set().union(*self.deps_by_cpu.values())

    @property
    def should_compile_swiftinterface(self) -> bool:
        return bool(self.swiftinterface_paths_by_cpu)

    def _render_deps(self, out: TextIO) -> None:
        shared_deps = set(self.all_dependencies)
        if not shared_deps:
            return

        cpus = sorted(self.deps_by_cpu)
        cpu_specific_deps = {cpu: self.deps_by_cpu[cpu] - shared_deps for cpu in cpus}
        has_cpu_specific_deps = any(cpu_specific_deps.values())
        if not has_cpu_specific_deps:
            out.write("    modules = [\n")
            _write_labels(out, shared_deps)
            out.write("    ],\n")
            return

        if shared_deps:
            out.write("    modules = [\n")
            _write_labels(out, shared_deps)
            out.write("    ] + select({\n")
        else:
            out.write("    modules = select({\n")
        for cpu, deps in cpu_specific_deps.items():
            if deps:
                out.write(f'        "{cpu}": [\n')
                _write_labels(out, deps, "            ")
                out.write("        ],\n")
            else:
                out.write(f'        "{cpu}": [],\n')

        out.write("    }),\n")

    def render_target(self, out: TextIO) -> None:
        if self.module_type == "clang":
            assert self.module_map_path
            out.write("\n")
            out.write("system_clang_module(\n")
            out.write(
                f'    name = "{_canonical_name(self.name, self.sdk, self.module_type)}",\n'
            )
            out.write(f'    module_name = "{self.name}",\n')
            self._render_deps(out)
            _write_transition_attrs(
                out,
                sdk=self.sdk,
                sdk_version=self.sdk_version,
            )
            out.write(f'    system_module_map = "{self.module_map_path}",\n')
            out.write(")\n")
        elif self.module_type == "swift":
            out.write("\n")
            if self.should_compile_swiftinterface:
                out.write("system_swiftinterface(\n")
            else:
                out.write("system_module_group(\n")
            out.write(
                f'    name = "{_canonical_name(self.name, self.sdk, self.module_type)}",\n'
            )
            if self.should_compile_swiftinterface:
                if self.is_framework:
                    out.write("    is_framework = True,\n")
                out.write(f'    module_name = "{self.name}",\n')
                self._render_deps(out)
                _write_string_attr(
                    out,
                    name="system_swiftinterface",
                    values_by_cpu=self.swiftinterface_paths_by_cpu,
                )
                _write_transition_attrs(
                    out,
                    sdk=self.sdk,
                    sdk_version=self.sdk_version,
                )
            else:
                self._render_deps(out)
            out.write(")\n")
        else:
            raise SystemExit(
                f"unexpected module type: {self.module_type} for {self.name}"
            )


def _parse_output(
    *,
    output: dict[str, Any],
    sdk: str,
    sdk_version: str,
    cpu: str,
    developer_dir: str,
    sdkroot: str,
    all_modules: dict[tuple[str, str], _Module],
) -> None:
    modules_json = output["modules"][2:]  # Skip the stub file pair
    for i in range(0, len(modules_json), 2):  # (header, body) pairs one after another
        type_json = modules_json[i]
        assert len(type_json) == 1, f"error: unexpected module header: {type_json}"
        key = next(iter(type_json.items()))
        module_type, module_name = key

        body = modules_json[i + 1]
        details = body["details"][module_type]
        deps = []
        for dep in body["directDependencies"] + details.get(
            "swiftOverlayDependencies", []
        ):
            deps.extend(dep.items())

        module = all_modules.get(key)
        module_map_path = _normalize_system_path(
            details.get("moduleMapPath", ""),
            developer_dir=developer_dir,
            sdkroot=sdkroot,
        )
        if module is None:
            module = all_modules[key] = _Module(
                name=module_name,
                module_type=module_type,
                sdk=sdk,
                sdk_version=sdk_version,
                module_map_path=module_map_path,
            )

        module.module_map_path = module.module_map_path or module_map_path
        if module_type == "swift":
            has_prebuilt_swiftmodule = bool(details.get("compiledModuleCandidates", []))
            if not has_prebuilt_swiftmodule:
                module.set_swiftinterface(
                    cpu=cpu,
                    is_framework=bool(details.get("isFramework", False)),
                    swiftinterface_path=_normalize_system_path(
                        details["moduleInterfacePath"],
                        developer_dir=developer_dir,
                        sdkroot=sdkroot,
                    ),
                )

        module.set_deps(cpu, deps)


def _strip_yaml_comment(line: str) -> str:
    return line.split("#", 1)[0].strip()


def _parse_yaml_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def _get_overlay_deps(path: Path) -> tuple[str, ...]:
    version = None
    modules = []
    in_modules = False
    pending_module = False

    for raw_line in path.read_text().splitlines():
        line = _strip_yaml_comment(raw_line)
        if not line or line == "---":
            continue

        if line.startswith("version:"):
            version = _parse_yaml_scalar(line.partition(":")[2])
            continue

        if line == "modules:":
            in_modules = True
            continue

        if not in_modules:
            raise ValueError(f"{path}: unexpected line before modules: {raw_line}")

        if line == "-":
            pending_module = True
            continue

        if line.startswith("- "):
            entry = line[2:].strip()
            if not entry.startswith("name:"):
                raise ValueError(f"{path}: expected module name entry: {raw_line}")
            modules.append(_parse_yaml_scalar(entry.partition(":")[2]))
            pending_module = False
            continue

        if pending_module and line.startswith("name:"):
            modules.append(_parse_yaml_scalar(line.partition(":")[2]))
            pending_module = False
            continue

        raise ValueError(f"{path}: unexpected modules entry: {raw_line}")

    if version != "1":
        raise ValueError(f"{path}: expected version: 1, got {version!r}")
    if not modules:
        raise ValueError(f"{path}: expected at least one overlay module")
    return tuple(modules)


def _discover_cross_import_overlays(
    *,
    cross_import_dirs: set[Path],
    developer_dir: str,
    sdk: str,
    sdk_path: str,
    all_modules: set[str],
) -> list[_CrossImportOverlay]:
    overlays = []
    for cross_import_dir in cross_import_dirs:
        for overlay_file in cross_import_dir.glob("*.swiftoverlay"):
            # The SDK can contain overlays referencing modules they don't ship.
            # For example there are some overlays in the macOS SDK that depend
            # on UIKit
            if (
                cross_import_dir.stem not in all_modules
                or overlay_file.stem not in all_modules
            ):
                continue

            overlays.append(
                _CrossImportOverlay(
                    declaring_module=cross_import_dir.stem,
                    bystanding_module=overlay_file.stem,
                    overlay_modules=_get_overlay_deps(overlay_file),
                    sdk=sdk,
                    swiftoverlay_path=_normalize_system_path(
                        overlay_file.as_posix(),
                        developer_dir=developer_dir,
                        sdkroot=sdk_path,
                    ),
                )
            )
    return sorted(overlays)


def _get_deployment_target(sdk: str, sdk_path: Path) -> str:
    settings = sdk_path / "SDKSettings.json"
    with open(settings) as f:
        output = json.load(f)

    return output["SupportedTargets"][sdk.lower()]["DefaultDeploymentTarget"]


def _scan(
    *,
    sdk: str,
    modules: set[str],
    sdk_path: Path,
    target: str,
    framework_search_paths: list[Path],
    swift_search_paths: list[Path],
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix=f"scan_{sdk}_") as tmp:
        workdir = Path(tmp)
        stub = workdir / "stub.swift"
        out_json = workdir / "scan.json"
        stub.write_text(
            "\n".join(f"import {m}" for m in sorted(modules)) + "\n",
        )
        cmd = (
            [
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
            ]
            + [f"-F{p}" for p in framework_search_paths]
            + [f"-I{p}" for p in swift_search_paths]
        )
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(
                f"[{sdk}] swiftc -scan-dependencies exited {res.returncode}:\n{res.stderr}"
            )

        return json.loads(out_json.read_text())


def _parse_modulemap_for_modules(modulemap_path: Path) -> set[str]:
    modules = set()
    for line in modulemap_path.read_text().splitlines():
        line = line.strip()
        if line.startswith("module "):
            module_name = line.split()[1]
            modules.add(module_name)
        elif line.startswith("extern module "):
            module_name = line.split()[2]
            modules.add(module_name)
    return modules


def _discover_all_modules(
    developer_dir: Path,
    sdk: str,
    excluded_modules: set[str],
) -> tuple[str, set[str]]:
    platform_developer_path = developer_dir / f"Platforms/{sdk}.platform/Developer"
    sdk_path = platform_developer_path / f"SDKs/{sdk}.sdk"
    framework_search_paths = [
        platform_developer_path / "Library/Frameworks",
        sdk_path / "System/Library/Frameworks",
    ]
    swift_search_paths = [
        platform_developer_path / "usr/lib",
    ]
    library_search_paths = [
        sdk_path / "usr/lib/swift",
        sdk_path / "usr/include",
    ]

    modules: set[str] = set()
    cross_import_dirs: set[Path] = set()
    for directory in set(
        framework_search_paths + library_search_paths + swift_search_paths
    ):
        for x in directory.iterdir():
            if x.stem in excluded_modules:
                continue
            if x.suffix == ".swiftcrossimport":
                modules.add(x.stem)
                cross_import_dirs.add(x)
                continue
            if not x.is_dir():
                if x.suffix == ".modulemap":
                    if x.stem == "module":
                        modules |= _parse_modulemap_for_modules(x)
                    else:
                        modules.add(x.stem)
                continue
            if x.suffix == ".swiftmodule":
                modules.add(x.stem)
            elif x.suffix == ".framework":
                modules_dir = x / "Modules"
                if (modules_dir / "module.modulemap").exists() or (
                    modules_dir / (x.stem + ".swiftmodule")
                ).exists():
                    modules.add(x.stem)
                    cross_import_dir = modules_dir / f"{x.stem}.swiftcrossimport"
                    if cross_import_dir.is_dir():
                        cross_import_dirs.add(cross_import_dir)
            elif (x / "module.modulemap").exists():
                modules.add(x.stem)  # /usr/include/CommonCrypto/module.modulemap

    deployment_target = _get_deployment_target(sdk, sdk_path)
    cpu_targets = _TARGETS_PER_SDK[sdk.lower()]
    cross_import_overlays = _discover_cross_import_overlays(
        cross_import_dirs=cross_import_dirs,
        developer_dir=developer_dir.as_posix(),
        sdk=sdk,
        sdk_path=sdk_path.as_posix(),
        all_modules=modules,
    )

    with ThreadPoolExecutor(max_workers=len(cpu_targets)) as pool:
        scan_futures = {
            pool.submit(
                _scan,
                sdk=sdk,
                modules=modules,
                sdk_path=sdk_path,
                target=target_format.format(ver=deployment_target),
                framework_search_paths=framework_search_paths,
                swift_search_paths=swift_search_paths,
            ): cpu
            for cpu, target_format in cpu_targets
        }
        scan_outputs = {
            scan_futures[fut]: fut.result() for fut in as_completed(scan_futures)
        }

    merged_modules: dict[tuple[str, str], _Module] = {}
    for cpu, _ in cpu_targets:
        _parse_output(
            output=scan_outputs[cpu],
            sdk=sdk,
            sdk_version=deployment_target,
            cpu=cpu,
            developer_dir=developer_dir.as_posix(),
            sdkroot=sdk_path.as_posix(),
            all_modules=merged_modules,
        )

    all_modules = sorted(merged_modules.values())
    swift_names = {m.name for m in all_modules if m.module_type == "swift"}
    clang_names = {m.name for m in all_modules if m.module_type == "clang"}
    all_module_names = swift_names | clang_names

    buf = io.StringIO()
    for module in all_modules:
        module.render_target(buf)
    _render_cross_import_overlay_targets(cross_import_overlays, sdk, buf)
    _render_clang_module_groups(
        all_modules,
        clang_names - swift_names,
        sdk,
        buf,
    )
    _render_all_modules_group(all_module_names, sdk, buf)

    return buf.getvalue(), all_module_names | {f"{n}_clang" for n in clang_names}


def _parse_exclude_modules(values: list[str]) -> dict[str, set[str]]:
    if not values:
        return {sdk: set(modules) for sdk, modules in _DEFAULT_EXCLUDED_MODULES.items()}

    excluded_modules: defaultdict[str, set[str]] = defaultdict(set)
    for value in values:
        sdk, sep, module = value.partition(":")
        if not sep or not sdk or not module:
            raise SystemExit(
                "error: --exclude-module values must be formatted as 'SDK:Module'"
            )
        if sdk not in _SDK_CONSTRAINTS:
            raise SystemExit(
                f"error: unknown SDK in --exclude-module '{sdk}'. Valid options are: {sorted(_SDK_CONSTRAINTS)}"
            )
        excluded_modules[sdk].add(module)
    return dict(excluded_modules)


def _main() -> None:
    parser = argparse.ArgumentParser(
        description="Scan Xcode and generate a BUILD file describing every system module.",
    )
    parser.add_argument(
        "-o",
        "--output",
        required=True,
        type=Path,
        help="Path to write the generated BUILD file. Required.",
    )
    parser.add_argument(
        "--developer-dir",
        type=Path,
        default=None,
        help=(
            "Path to the Xcode `Developer/` directory to scan. If omitted, "
            "the `DEVELOPER_DIR` environment variable is used."
        ),
    )
    parser.add_argument(
        "--module-names",
        type=Path,
        default=None,
        # Internal flag used by the `system_sdk` module extension; not part
        # of the user-facing CLI.
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--exclude-module",
        action="append",
        default=[],
        metavar="SDK:MODULE",
        help=(
            "Exclude a module from a specific SDK scan. May be repeated "
            "(for example: --exclude-module WatchOS:BrowserEngineKit)."
        ),
    )
    parser.add_argument(
        "sdks",
        nargs="*",
        help=(
            "SDK names to scan (e.g. MacOSX, iPhoneOS). If omitted, every "
            "SDK installed in the Xcode is scanned."
        ),
    )
    args = parser.parse_args()

    if args.developer_dir is not None:
        developer_dir = args.developer_dir
    elif os.environ.get("DEVELOPER_DIR"):
        developer_dir = Path(os.environ["DEVELOPER_DIR"])
    else:
        raise SystemExit(
            "error: --developer-dir was not given and DEVELOPER_DIR is not set"
        )

    if args.sdks:
        unknown = [s for s in args.sdks if s not in _SDK_CONSTRAINTS]
        if unknown:
            raise SystemExit(
                f"error: unknown SDK(s): '{unknown}'. Valid options are: {sorted(_SDK_CONSTRAINTS)}"
            )
        sdk_names = sorted(set(args.sdks))
    else:
        sdk_names = sorted(_SDK_CONSTRAINTS.keys())

    excluded_modules = _parse_exclude_modules(args.exclude_module)

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
            pool.submit(
                _discover_all_modules,
                developer_dir,
                sdk,
                excluded_modules.get(sdk, set()),
            ): sdk
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
    buf.write('        "@platforms//os:none": ":_empty_all_modules",\n')
    buf.write("    }),\n")
    buf.write(")\n")

    buf.write("\n")
    buf.write("alias(\n")
    buf.write('    name = "all_cross_import_overlays",\n')
    buf.write("    actual = select({\n")
    for sdk in sdk_names:
        if all_modules_by_sdk.get(sdk):
            buf.write(f'        ":{sdk}_sdk": ":{sdk}_all_cross_import_overlays",\n')
    buf.write('        "@platforms//os:none": ":_empty_cross_import_overlays",\n')
    buf.write("    }),\n")
    buf.write(")\n")

    with open(args.output, "w") as f:
        f.write(buf.getvalue())

    if args.module_names is not None:
        with open(args.module_names, "w") as f:
            json.dump(sorted(all_modules), f, indent=2)


if __name__ == "__main__":
    _main()

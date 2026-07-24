#!/usr/bin/env python3

"""Generate Swift release metadata JSON files from swift.org."""

from __future__ import annotations

import hashlib
import json
from collections import OrderedDict
from pathlib import Path
from typing import Any
from urllib.request import urlopen


_SWIFT_RELEASES_URL = "https://www.swift.org/api/v1/install/releases.json"
_REPO_ROOT = Path(__file__).resolve().parent.parent
_METADATA_JSON = _REPO_ROOT / "swift/internal/extensions/swift_release_metadata.json"
_DOWNLOAD_CACHE = Path("/tmp/rules_swift_release_download_cache")
_MIN_VERSION = "6.2.1"  # Chosen at random
_SDK_PLATFORMS = {
    "android-sdk": "android",
    "wasm-sdk": "wasm",
}


def _version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open() as file:
        return json.load(file)


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as file:
        json.dump(data, file, indent=2)
        file.write("\n")


def _fetch_upstream_releases() -> list[dict[str, Any]]:
    with urlopen(_SWIFT_RELEASES_URL) as response:
        if response.status != 200:
            raise RuntimeError(
                f"GET {_SWIFT_RELEASES_URL} returned HTTP {response.status}"
            )
        return json.load(response)


def _platform_key(platform: dict[str, Any], arch: str) -> str | None:
    if arch not in ("x86_64", "aarch64"):
        return None

    platform_name = platform.get("dir")
    if not platform_name:
        platform_name = platform["name"].lower().replace(" ", "")

    if arch == "x86_64":
        return platform_name
    return f"{platform_name}-{arch}"


def _toolchain_platform_keys(release: dict[str, Any]) -> list[str]:
    keys = []
    for platform in release.get("platforms", []):
        if platform.get("platform") != "Linux":
            continue
        for arch in platform.get("archs", []):
            key = _platform_key(platform, arch)
            if key:
                keys.append(key)

    if release.get("xcode"):
        keys.append("xcode")

    return sorted(set(keys))


def _sdk_releases(releases: list[dict[str, Any]]) -> dict[str, dict[str, str]]:
    result = OrderedDict()
    for release in releases:
        sdks = {}
        for platform in release.get("platforms", []):
            sdk = _SDK_PLATFORMS.get(platform.get("platform"))
            checksum = platform.get("checksum")
            if sdk and checksum:
                sdks[sdk] = checksum
        if sdks:
            result[release["name"]] = OrderedDict(
                (sdk, sdks[sdk]) for sdk in sorted(sdks)
            )
    return result


def _swift_release_tag(version: str) -> str:
    return f"swift-{version}-RELEASE"


def _swift_release_category(version: str) -> str:
    return f"swift-{version}-release"


def _download_filename(version: str, platform: str) -> str:
    tag = _swift_release_tag(version)
    if platform == "xcode":
        return f"{tag}-osx.pkg"
    return f"{tag}-{platform}.tar.gz"


def _download_url(version: str, platform: str) -> str:
    tag = _swift_release_tag(version)
    platform_dir = platform.replace(".", "")
    filename = _download_filename(version, platform)
    return (
        f"https://download.swift.org/{_swift_release_category(version)}/"
        f"{platform_dir}/{tag}/{filename}"
    )


def _sha256_url(url: str) -> str:
    filename = url.rsplit("/", 1)[-1]
    cache_path = _DOWNLOAD_CACHE / filename

    if cache_path.exists():
        print(f"Hashing cached {cache_path}")
        digest = hashlib.sha256()
        with cache_path.open("rb") as file:
            while True:
                chunk = file.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
        return digest.hexdigest()

    print(f"Downloading and hashing {url}")
    _DOWNLOAD_CACHE.mkdir(parents=True, exist_ok=True)
    tmp_path = cache_path.with_suffix(cache_path.suffix + ".tmp")
    digest = hashlib.sha256()
    with urlopen(url) as response:
        if response.status != 200:
            raise RuntimeError(f"GET {url} returned HTTP {response.status}")
        with tmp_path.open("wb") as file:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                file.write(chunk)
    tmp_path.replace(cache_path)
    return digest.hexdigest()


def _toolchain_releases(
    releases: list[dict[str, Any]],
    existing: dict[str, dict[str, str]],
) -> dict[str, dict[str, str]]:
    result = OrderedDict()
    for release in releases:
        version = release["name"]
        existing_platforms = existing.get(version, {})
        platforms = OrderedDict()

        for platform in _toolchain_platform_keys(release):
            existing_checksum = existing_platforms.get(platform)
            if existing_checksum:
                platforms[platform] = existing_checksum
                continue

            url = _download_url(version, platform)
            platforms[platform] = _sha256_url(url)

        if platforms:
            result[version] = platforms
    return result


def _selected_releases(releases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    minimum = _version_key(_MIN_VERSION)
    selected = []

    for release in releases:
        try:
            current = _version_key(release["name"])
        except ValueError:
            continue
        if current < minimum:
            continue
        selected.append(release)

    return sorted(selected, key=lambda release: _version_key(release["name"]))


def _main() -> None:
    existing_metadata = _load_json(_METADATA_JSON)
    existing_toolchains = existing_metadata.get("toolchains", {})
    upstream = _fetch_upstream_releases()

    releases = _selected_releases(upstream)
    if not releases:
        raise RuntimeError(f"No Swift releases found at or after {_MIN_VERSION}")

    generated_toolchains = _toolchain_releases(
        releases,
        existing_toolchains,
    )
    generated_sdks = _sdk_releases(releases)

    _write_json(
        _METADATA_JSON,
        {
            "toolchains": generated_toolchains,
            "sdks": generated_sdks,
        },
    )

    print(
        "Wrote "
        f"{len(generated_toolchains)} toolchain releases and "
        f"{len(generated_sdks)} SDK releases to "
        f"{_METADATA_JSON}"
    )


if __name__ == "__main__":
    _main()

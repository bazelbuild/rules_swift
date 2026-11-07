#!/bin/bash
# make_msvc_sysroot.ps1's archive made usable on Linux: the links a
# case-sensitive file system needs for the casings Windows' headers, its
# `#pragma comment(lib)`s and Swift's module maps use (case_links.swift),
# then archived again with a VERSIONS file naming MSVC's and the SDK's.
#
#   tools/windows_sdk/make_msvc_sysroot.sh <winsysroot.tar.gz> <swift-windows-sdk.tar.gz> <out.tar.gz>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
in="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
swift_sdk="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
out="$3"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -xzf "$in" -C "$work"
tar -xzf "$swift_sdk" -C "$work" --wildcards 'swift-windows-sdk/Windows.platform/Developer/SDKs/Windows.sdk/usr/share/*'
swift "$here/case_links.swift" "$work/winsysroot" \
    "$work/swift-windows-sdk/Windows.platform/Developer/SDKs/Windows.sdk/usr/share"
{
    echo "msvc=$(ls "$work/winsysroot/VC/Tools/MSVC")"
    echo "sdk=$(ls "$work/winsysroot/Windows Kits/10/Include")"
} >"$work/winsysroot/VERSIONS"
tar -czf "$out" -C "$work" winsysroot
echo "make_msvc_sysroot.sh: $out: $(du -h "$out" | cut -f1)"; cat "$work/winsysroot/VERSIONS"

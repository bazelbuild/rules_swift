#!/bin/bash
# The Windows Swift SDK for building on Linux, out of swift.org's Windows
# toolchain installer: its Windows.platform (the SDK the compiler builds
# against, XCTest and Testing beside it) and the runtime's DLLs for arm64
# and x64 (what an app ships beside its .exe), as one archive. Run on Linux
# with 7-Zip and msitools (apt: 7zip msitools); then host the archive and
# name it in `swift.windows_sdk` (README.md).
#
#   tools/windows_sdk/make_swift_sdk.sh <swift-X.Y.Z-RELEASE-windows10-arm64.exe> <out.tar.gz>
set -euo pipefail
installer="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

# A WiX bundle: its own cabinet, then the payloads' (the attached
# container), each payload named a0…aN, mapped to its file by the bundle's
# manifest (the first cabinet's file "0").
7z e -y -oux "$installer" 0 >/dev/null
offsets=($(grep -obUaP 'MSCF\x00\x00\x00\x00' "$installer" | cut -d: -f1))
[ ${#offsets[@]} -ge 2 ] || { echo "make_swift_sdk.sh: no attached container in $installer" >&2; exit 1; }
tail -c +$((offsets[1] + 1)) "$installer" >attached.cab
7z e -y -opayloads attached.cab >/dev/null
mkdir msi
grep -o '<Payload [^>]*>' ux/0 | while read -r payload; do
    file="$(sed -n 's/.*FilePath="\([^"]*\)".*/\1/p' <<<"$payload")"
    source="$(sed -n 's/.*SourcePath="\([^"]*\)".*/\1/p' <<<"$payload")"
    [ -f "payloads/$source" ] && cp "payloads/$source" "msi/$file"
done

msiextract -C extracted msi/windows.msi >/dev/null
msiextract -C extracted msi/rtl.msi >/dev/null
swift="extracted/LocalApp/Programs/Swift"
version="$(ls "$swift/Platforms")"
mkdir -p "sdk/swift-windows-sdk"
cp -a "$swift/Platforms/$version/Windows.platform" sdk/swift-windows-sdk/
# The runtime's merge modules: a cabinet of files keyed by id, named in
# the module's File table.
for arch in arm64:aarch64 amd64:x86_64; do
    module="$swift/Redistributables/$version/rtl.${arch%%:*}.msm"
    mkdir -p "rtl-${arch%%:*}" "sdk/swift-windows-sdk/runtime/${arch##*:}"
    (cd "rtl-${arch%%:*}" && 7z x -y "$work/$module" >/dev/null && 7z x -y MergeModule.CABinet -ofiles >/dev/null)
    msiinfo export "$module" File | tail -n +4 | while IFS=$'\t' read -r key _ name _; do
        [ -f "rtl-${arch%%:*}/files/$key" ] && cp "rtl-${arch%%:*}/files/$key" "sdk/swift-windows-sdk/runtime/${arch##*:}/${name#*|}"
    done
done
printf '%s\n' "$version" >sdk/swift-windows-sdk/VERSION
tar -czf "$out" -C sdk swift-windows-sdk
echo "make_swift_sdk.sh: $out (Swift $version): $(du -h "$out" | cut -f1)"

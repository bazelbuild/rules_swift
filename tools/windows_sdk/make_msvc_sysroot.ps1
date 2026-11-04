# Microsoft's half of building for Windows on Linux, made on a Windows machine
# with the Visual Studio Build Tools: the Windows SDK's headers (ucrt, um, shared, winrt) and its
# arm64 and x64 import libraries, and MSVC's headers and libraries, in
# clang's /winsysroot layout (VC/Tools/MSVC/<version>, Windows Kits/10), as
# C:\winsysroot.tar.gz. make_msvc_sysroot.sh then adds the links a
# case-sensitive file system needs. Never published: Microsoft's license
# lets it be used, not redistributed (README.md).
#
#   powershell -File make_msvc_sysroot.ps1 [-SdkVersion 10.0.22621.0]
param([string]$SdkVersion = '')
$ErrorActionPreference = 'Stop'
$kitsRoot = 'C:\Program Files (x86)\Windows Kits\10'
if (-not $SdkVersion) { $SdkVersion = (Get-ChildItem "$kitsRoot\Include" | Sort-Object Name | Select-Object -Last 1).Name }
$msvc = Get-ChildItem 'C:\Program Files*\Microsoft Visual Studio\*\*\VC\Tools\MSVC' -Directory | Sort-Object Name | Select-Object -Last 1
$root = 'C:\winsysroot'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
$kits = "$root\Windows Kits\10"
New-Item -ItemType Directory -Force "$kits\Include\$SdkVersion", "$kits\Lib\$SdkVersion\ucrt", "$kits\Lib\$SdkVersion\um", "$root\VC\Tools\MSVC\$($msvc.Name)\lib" | Out-Null
foreach ($area in 'ucrt', 'um', 'shared', 'winrt') { Copy-Item -Recurse "$kitsRoot\Include\$SdkVersion\$area" "$kits\Include\$SdkVersion\$area" }
foreach ($area in 'ucrt', 'um') { foreach ($arch in 'arm64', 'x64') { Copy-Item -Recurse "$kitsRoot\Lib\$SdkVersion\$area\$arch" "$kits\Lib\$SdkVersion\$area\$arch" } }
Copy-Item -Recurse "$($msvc.FullName)\include" "$root\VC\Tools\MSVC\$($msvc.Name)\include"
foreach ($arch in 'arm64', 'x64') { Copy-Item -Recurse "$($msvc.FullName)\lib\$arch" "$root\VC\Tools\MSVC\$($msvc.Name)\lib\$arch" }
Set-Location C:\
if (Test-Path C:\winsysroot.tar.gz) { Remove-Item C:\winsysroot.tar.gz }
tar -czf C:\winsysroot.tar.gz winsysroot
"MSVC $($msvc.Name), Windows SDK $SdkVersion: C:\winsysroot.tar.gz"

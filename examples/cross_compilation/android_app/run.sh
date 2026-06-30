#!/usr/bin/env bash

# `bazel run //examples/cross_compilation/android_app:run`: installs the example
# APK on a connected device/emulator and launches it. If nothing is connected,
# boots the hermetic emulator (downloaded emulator + AOSP system image) first.

set -euo pipefail

RUNFILES_ROOT="$PWD/.."
APK="$RUNFILES_ROOT/$1"
ADB="$RUNFILES_ROOT/$2"
EMULATOR_BIN="$RUNFILES_ROOT/$3"
SYSIMG_MARKER="$RUNFILES_ROOT/$4"

has_device() {
  "$ADB" devices | awk 'NR>1 && $2 == "device"' | grep -q .
}

is_boot_completed() {
  [[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]
}

is_package_manager_ready() {
  "$ADB" shell service check package 2>/dev/null | grep -q ": found" &&
    "$ADB" shell service check settings 2>/dev/null | grep -q ": found" &&
    "$ADB" shell cmd package path android >/dev/null 2>&1
}

"$ADB" start-server >/dev/null 2>&1 || true

if ! has_device; then
  echo "No device connected; booting the hermetic emulator..."
  EMULATOR_DIR="$(cd "$(dirname "$EMULATOR_BIN")" && pwd)"
  SYSIMG_DIR="$(cd "$(dirname "$SYSIMG_MARKER")" && pwd)"

  STATE="${TMPDIR:-/tmp}/rules_swift_android_example_emulator"
  SDK="$STATE/sdk"
  AVD_HOME="$STATE/avd"
  AVD_DIR="$AVD_HOME/example.avd"
  mkdir -p "$SDK/system-images/android-34/default" "$AVD_DIR" "$SDK/platform-tools"

  ln -sfn "$EMULATOR_DIR" "$SDK/emulator"
  ln -sfn "$SYSIMG_DIR" "$SDK/system-images/android-34/default/arm64-v8a"
  ln -sfn "$ADB" "$SDK/platform-tools/adb"

  cat > "$AVD_HOME/example.ini" <<EOF
avd.ini.encoding=UTF-8
path=$AVD_DIR
target=android-34
EOF

  if [[ ! -f "$AVD_DIR/config.ini" ]]; then
    cat > "$AVD_DIR/config.ini" <<EOF
AvdId=example
avd.ini.displayname=rules_swift Android example
abi.type=arm64-v8a
hw.cpu.arch=arm64
image.sysdir.1=system-images/android-34/default/arm64-v8a/
tag.id=default
hw.gpu.enabled=yes
hw.gpu.mode=auto
hw.ramSize=2048
hw.lcd.density=420
hw.lcd.width=1080
hw.lcd.height=1920
PlayStore.enabled=false
EOF
  fi

  export ANDROID_SDK_ROOT="$SDK"
  export ANDROID_AVD_HOME="$AVD_HOME"
  EMULATOR_LOG="$STATE/emulator.log"
  "$SDK/emulator/emulator" -avd example -no-audio -no-boot-anim -no-snapshot >"$EMULATOR_LOG" 2>&1 &
  echo "  (emulator log: $EMULATOR_LOG)"

  "$ADB" wait-for-device
  for _ in $(seq 1 120); do
    is_boot_completed && is_package_manager_ready && break
    sleep 2
  done
  has_device || { echo "error: emulator failed to boot; see $EMULATOR_LOG" >&2; exit 1; }
  is_boot_completed || { echo "error: emulator did not complete boot; see $EMULATOR_LOG" >&2; exit 1; }
  is_package_manager_ready || { echo "error: emulator booted, but package manager is not ready; see $EMULATOR_LOG" >&2; exit 1; }
  echo "Emulator booted."
fi

"$ADB" install -r "$APK"
"$ADB" shell am start -n "com.example.swiftjni/.MainActivity"
echo "Launched com.example.swiftjni/.MainActivity"

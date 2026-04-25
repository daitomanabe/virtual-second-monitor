#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_name="Virtual Second Monitor"
bundle="$root_dir/build/$app_name.app"
contents="$bundle/Contents"
macos="$contents/MacOS"
resources="$contents/Resources"

rm -rf "$bundle"
mkdir -p "$macos" "$resources"

clang++ \
  -std=c++17 \
  -fobjc-arc \
  -fmodules \
  -Wall \
  -Wextra \
  -Wno-unguarded-availability-new \
  -framework AppKit \
  -framework Foundation \
  -framework CoreGraphics \
  -weak_framework ScreenCaptureKit \
  -framework QuartzCore \
  "$root_dir/native/VirtualSecondMonitorApp.mm" \
  -o "$macos/$app_name"

cp "$root_dir/native/VirtualSecondMonitorApp-Info.plist" "$contents/Info.plist"
plutil -lint "$contents/Info.plist" >/dev/null

if command -v codesign >/dev/null 2>&1; then
  codesign_identity="${CODESIGN_IDENTITY:--}"
  codesign --force --deep --sign "$codesign_identity" "$bundle" >/dev/null
fi

echo "$bundle"

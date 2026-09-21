#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root_dir/build"
clang++ -std=c++17 -fobjc-arc -fmodules -Wall -Wextra -Wno-unguarded-availability-new \
  -framework AppKit -framework Foundation -framework CoreGraphics \
  -weak_framework ScreenCaptureKit -framework QuartzCore \
  "$root_dir/native/VSMDisplayManager.mm" "$root_dir/tests/AppTests.mm" \
  -o "$root_dir/build/app-tests"
"$root_dir/build/app-tests"

#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root_dir/build"

clang++ \
  -std=c++17 \
  -fobjc-arc \
  -fmodules \
  -Wall \
  -Wextra \
  -Wno-unguarded-availability-new \
  -framework Foundation \
  -framework CoreGraphics \
  "$root_dir/native/VirtualSecondMonitor.mm" \
  -o "$root_dir/build/virtual-second-monitor"

echo "$root_dir/build/virtual-second-monitor"

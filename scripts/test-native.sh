#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root_dir/build"
clang++ -std=c++17 -fobjc-arc -fmodules -Wall -Wextra \
  -framework Foundation -framework CoreGraphics \
  "$root_dir/native/VSMDisplayManager.mm" "$root_dir/tests/DisplayManagerTests.mm" \
  -o "$root_dir/build/display-manager-tests"
"$root_dir/build/display-manager-tests"
"$root_dir/scripts/build-native.sh"
python3 "$root_dir/tests/test_cli.py"

#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -x "$root_dir/build/virtual-second-monitor" ]; then
  "$root_dir/scripts/build-native.sh" >/dev/null
fi

exec "$root_dir/build/virtual-second-monitor" \
  --width 1920 \
  --height 1080 \
  --ppi 110 \
  --refresh 60 \
  --name "Debug Second Display"
